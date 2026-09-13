$ErrorActionPreference = 'Stop'
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('mubangumi-build-test-' + [guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path (Join-Path $testRoot 'tool'), (Join-Path $testRoot 'config') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\build_release.ps1') -Destination (Join-Path $testRoot 'tool\build_release.ps1')
# Only synthetic credentials are used; the real workspace configuration is never read.
'{"BGM_CLIENT_ID":"fixture-id","BGM_CLIENT_SECRET":"fixture-secret"}' | Set-Content -LiteralPath (Join-Path $testRoot 'config\oauth.local.json') -Encoding utf8
$fixture = @{ Calls = [Collections.Generic.List[object]]::new(); OmitAbi = ''; OmitSymbols = $false; FailBuild = $false }
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Write-FixtureFile([string]$Relative) {
    $path = Join-Path (Get-Location).Path $Relative
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($path, 'build-fixture')
}

function flutter {
    $fixture.Calls.Add(@($args))
    if ($fixture.FailBuild) { $global:LASTEXITCODE = 7; return }
    $symbolArgument = @($args | Where-Object { $_ -like '--split-debug-info=*' })
    if ($symbolArgument.Count -and -not $fixture.OmitSymbols) {
        $symbolPath = $symbolArgument[0].Substring('--split-debug-info='.Length)
        foreach ($platform in @('android-arm', 'android-arm64', 'android-x64')) {
            [IO.File]::WriteAllText((Join-Path $symbolPath "app.$platform.symbols"), 'symbols-fixture')
        }
    }
    switch ($args[1]) {
        'apk' {
            foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
                if ($abi -ne $fixture.OmitAbi) {
                    Write-FixtureFile "build\app\outputs\flutter-apk\app-$abi-release.apk"
                }
            }
        }
        'windows' {
            Write-FixtureFile 'build\windows\x64\runner\Release\mubangumi.exe'
            Write-FixtureFile 'build\windows\x64\runner\Release\data\app.so'
        }
        'appbundle' { Write-FixtureFile 'build\app\outputs\bundle\release\app-release.aab' }
    }
    $global:LASTEXITCODE = 0
}

function shorebird {
    $fixture.Calls.Add(@($args))
    if ($args -notcontains '--dry-run' -and $args[0] -eq 'release') {
        Write-FixtureFile 'build\app\outputs\flutter-apk\app-release.apk'
    }
    $global:LASTEXITCODE = 0
}

function Invoke-FixtureBuild {
    & (Join-Path $testRoot 'tool\build_release.ps1') @args
}

try {
    Invoke-FixtureBuild -Target apk -BuildName 2.2.0 -BuildNumber 25
    $call = $fixture.Calls[-1]
    Assert-True ($call -contains '--split-per-abi') 'APK must split architectures'
    Assert-True ($call -contains '--tree-shake-icons') 'Icon trimming must be enabled'
    Assert-True ($call -contains '--build-name=2.2.0' -and $call -contains '--build-number=25') 'Version overrides lost'
    Assert-True (($call -join ' ') -notmatch 'fixture-secret') 'Credentials leaked into command arguments'
    $manifests = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'release-symbols') -Recurse -Filter build.json)
    $manifest = Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
    Assert-True ($manifest.Artifacts.Count -eq 3) 'Manifest must include all three APKs'
    foreach ($record in $manifest.Artifacts) {
        $actual = Get-FileHash -LiteralPath (Join-Path $testRoot ('build\app\outputs\flutter-apk\' + $record.File)) -Algorithm SHA256
        Assert-True ($actual.Hash -eq $record.SHA256) 'Manifest hash mismatch'
    }
    $passed++

    # A previous valid APK must not hide a partial success in a subsequent build.
    $fixture.OmitAbi = 'x86_64'
    $rejected = $false
    try { Invoke-FixtureBuild -Target apk } catch { $rejected = $true }
    Assert-True $rejected 'Partial build accepted an old APK'
    $fixture.OmitAbi = ''
    $passed++

    Invoke-FixtureBuild -Target apk -BuildName 2.2.0 -BuildNumber 25
    $manifests = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'release-symbols') -Recurse -Filter build.json)
    Assert-True ($manifests.Count -eq 2) 'Rebuild overwrote old symbols or recorded an incomplete build'
    $passed++

    foreach ($target in @('windows', 'appbundle')) {
        Invoke-FixtureBuild -Target $target
        Assert-True ($fixture.Calls[-1] -notcontains '--split-per-abi') 'APK-only flag passed to other target'
        $passed++
    }

    $fixture.OmitSymbols = $true
    $rejected = $false
    try { Invoke-FixtureBuild -Target windows } catch { $rejected = $true }
    Assert-True $rejected 'Build without debugging symbols accepted'
    $fixture.OmitSymbols = $false
    $passed++

    $fixture.FailBuild = $true
    $rejected = $false
    try { Invoke-FixtureBuild -Target apk } catch { $rejected = $true }
    Assert-True $rejected 'Failed compiler accepted'
    $fixture.FailBuild = $false
    $passed++

    Invoke-FixtureBuild -Target apk -Shorebird -BuildNumber 25
    Assert-True ($fixture.Calls[-1] -contains '--artifact=apk') 'Shorebird APK artifact option lost'
    Assert-True ($fixture.Calls[-1] -notcontains '--split-per-abi') 'Existing Shorebird compilation changed'
    Invoke-FixtureBuild -Target apk -Patch -ReleaseVersion '2.2.0+24' -DryRun
    Assert-True ($fixture.Calls[-1] -contains '--release-version=2.2.0+24') 'Patch baseline lost'
    Assert-True ($fixture.Calls[-1] -contains '--dry-run') 'Patch dry run lost'
    $rejected = $false
    try { Invoke-FixtureBuild -Target apk -Patch -ReleaseVersion '2.2.0+24' -BuildNumber 25 } catch { $rejected = $true }
    Assert-True $rejected 'Patch accepted a conflicting build version'
    $passed++
    Write-Output "Passed $passed release build checks."
} finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $testRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path $testRoot -Leaf).StartsWith('mubangumi-build-test-')) {
        throw 'Refusing cleanup outside generated test directory'
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
