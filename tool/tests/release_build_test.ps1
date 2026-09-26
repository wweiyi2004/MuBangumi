$ErrorActionPreference = 'Stop'
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('mubangumi-build-test-' + [guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path (Join-Path $testRoot 'tool'), (Join-Path $testRoot 'config') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\build_release.ps1') -Destination (Join-Path $testRoot 'tool\build_release.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\release_provenance.py') -Destination (Join-Path $testRoot 'tool\release_provenance.py')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\toolchain.json') -Destination (Join-Path $testRoot 'tool\toolchain.json')
@'
$script:MuVersions = Get-Content (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
function Get-MuFlutterRoot { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../sdk')) }
function Invoke-MuFlutter { param([string[]]$Arguments); flutter @Arguments }
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'tool\toolchain.ps1') -Encoding utf8
New-Item -ItemType Directory (Join-Path $testRoot 'sdk\bin\cache') -Force | Out-Null
$pinned = Get-Content (Join-Path $testRoot 'tool\toolchain.json') -Raw | ConvertFrom-Json
@{frameworkVersion=$pinned.flutter;engineRevision=$pinned.flutterEngineRevision;frameworkRevision=$pinned.flutterFrameworkRevision} | ConvertTo-Json | Set-Content (Join-Path $testRoot 'sdk\bin\cache\flutter.version.json')
'version: 2.2.0+24' | Set-Content (Join-Path $testRoot 'pubspec.yaml')
'fixture-locked-dependencies' | Set-Content (Join-Path $testRoot 'pubspec.lock')
@'
build/
config/
release-symbols/
sdk/
'@ | Set-Content (Join-Path $testRoot '.gitignore')
& git -C $testRoot init --quiet
& git -C $testRoot add .
& git -C $testRoot -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m fixture
# Only synthetic credentials are used; the real workspace configuration is never read.
'{"BGM_CLIENT_ID":"fixture-id","BGM_CLIENT_SECRET":"fixture-secret"}' | Set-Content -LiteralPath (Join-Path $testRoot 'config\oauth.local.json') -Encoding utf8
$fixture = @{ Calls = [Collections.Generic.List[object]]::new(); OmitAbi = ''; OmitSymbols = $false; FailBuild = $false; DriftLock = $false }
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
    if ($args[0] -eq 'pub') { $global:LASTEXITCODE = 0; return }
    if ($args -contains '--config-only') {
        if ($fixture.DriftLock) { Write-FixtureFile 'pubspec.lock' }
        $global:LASTEXITCODE = 0
        return
    }
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
            if ($args -notcontains '--split-per-abi') {
                if ($fixture.OmitAbi -ne 'universal') {
                    Write-FixtureFile 'build\app\outputs\flutter-apk\app-release.apk'
                }
                break
            }
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
    $source = (& python (Join-Path $testRoot 'tool\release_provenance.py') identity --root $testRoot | ConvertFrom-Json)
    $versionName='2.2.0'; $number='24'; $platform='windows'; $baseline=''
    for ($i=0;$i -lt $args.Count-1;$i++) {
        switch ($args[$i]) {
            '-Target' { if($args[$i+1] -ne 'windows'){$platform='android'} }
            '-BuildName' {$versionName=$args[$i+1]}
            '-BuildNumber' {$number=$args[$i+1]}
            '-ReleaseVersion' {$baseline=$args[$i+1]}
        }
    }
    $verification = Join-Path $testRoot 'config\verification.json'
    @{passed=$true;mode='Full';createdUtc=[DateTime]::UtcNow.ToString('o');source=$source;checks=@(@('flutter-analyze','flutter-tests','architecture','repository-privacy','provenance-tests','android-build','windows-build') | ForEach-Object {@{name=$_;status='passed'}})} | ConvertTo-Json -Depth 8 | Set-Content $verification
    $acceptance = Join-Path $testRoot 'config\acceptance.json'
    $cases=@{}; foreach($case in @('oauth_login','saved_session','session_expiry','website_challenge','network_recovery','foreground_resume','account_switch','pm_delivery','group_write')){$cases[$case]='passed'}
    @{platform=$platform;version=$(if($baseline){$baseline}else{"$versionName+$number"});source_fingerprint=$source.fingerprint;completedUtc=[DateTime]::UtcNow.ToString('o');evidence='synthetic test only';cases=$cases} | ConvertTo-Json -Depth 5 | Set-Content $acceptance
    & (Join-Path $testRoot 'tool\build_release.ps1') @args -VerificationReport $verification -AcceptanceReport $acceptance
}

try {
    Invoke-FixtureBuild -Target apk -BuildName 2.2.0 -BuildNumber 25 -GiteeRepository 'fixture/MuBangumi'
    $call = $fixture.Calls[-1]
    Assert-True ($fixture.Calls[0] -contains '--enforce-lockfile') 'Release must enforce the dependency lock before regenerating plugins'
    Assert-True ($fixture.Calls[1] -contains '--config-only' -and $fixture.Calls[1] -contains '--release' -and $fixture.Calls[1] -notcontains '--no-pub') 'Release plugin regeneration was skipped'
    Assert-True ($call -contains '--split-per-abi') 'APK must split architectures'
    Assert-True ($call -contains '--dart-define=GITEE_REPOSITORY=fixture/MuBangumi') 'Mirror configuration was not compiled into the application'
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
    $rejected = $false
    try { Invoke-FixtureBuild -Target apk -GiteeRepository 'https://gitee.com/fixture/MuBangumi' } catch { $rejected = $true }
    Assert-True $rejected 'Mirror configuration accepted a full URL instead of owner/repository'
    $passed++
    Invoke-FixtureBuild -Target apk -UniversalApk -BuildNumber 4030
    Assert-True ($fixture.Calls[-1] -notcontains '--split-per-abi') 'Universal APK must retain the exact build number'
    $fixture.OmitAbi = 'universal'
    $rejected = $false
    try { Invoke-FixtureBuild -Target apk -UniversalApk } catch { $rejected = $true }
    Assert-True $rejected 'Universal build accepted a stale APK'
    $fixture.OmitAbi = ''
    $rejected = $false
    try { Invoke-FixtureBuild -Target windows -UniversalApk } catch { $rejected = $true }
    Assert-True $rejected 'Universal APK flag accepted for a non-APK build'
    $passed++
    $fixture.DriftLock = $true
    $rejected = $false
    try { Invoke-FixtureBuild -Target apk } catch { $rejected = $true }
    Assert-True $rejected 'Release accepted dependency drift during plugin preparation'
    Assert-True ($fixture.Calls[-1] -contains '--config-only') 'Compiler ran after the dependency lock changed'
    $fixture.DriftLock = $false
    & git -C $testRoot restore -- pubspec.lock
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
