$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('mubangumi-cleanup-test-' + [guid]::NewGuid().ToString('N'))))
$fixtureRoot = Join-Path $testRoot 'repo'
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
# Do not depend on whether an unrelated project has a test runner open.
function Get-CimInstance { @() }
try {
    foreach ($directory in @('tool\maintenance','docs','.dart_tool','build\test_cache','dist')) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $directory) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tool\maintenance\clean_workspace.ps1') -Destination (Join-Path $fixtureRoot 'tool\maintenance\clean_workspace.ps1')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tool\windows_package_safety.ps1') -Destination (Join-Path $fixtureRoot 'tool\windows_package_safety.ps1')
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'pubspec.yaml'), 'name: fixture')
    & git -C $fixtureRoot init --quiet
    $clean = Join-Path $fixtureRoot ('.dart_tool\windows-package-' + ('a' * 32))
    $private = Join-Path $fixtureRoot ('.dart_tool\windows-package-' + ('b' * 32))
    $tracked = Join-Path $fixtureRoot ('.dart_tool\windows-package-' + ('c' * 32))
    foreach ($directory in @($clean,$private,$tracked)) {
        New-Item -ItemType Directory -Path (Join-Path $directory 'data\flutter_assets') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $directory 'mubangumi.exe'), 'fixture')
    }
    [IO.File]::WriteAllText((Join-Path $private 'data\flutter_assets\user.db'), 'private fixture')
    $outside = Join-Path $testRoot 'outside'
    New-Item -ItemType Directory -Path $outside | Out-Null
    [IO.File]::WriteAllText((Join-Path $outside 'keep.txt'), 'outside fixture')
    $link = Join-Path $fixtureRoot ('.dart_tool\windows-package-' + ('d' * 32))
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    & git -C $fixtureRoot add '.dart_tool/windows-package-cccccccccccccccccccccccccccccccc/mubangumi.exe'
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'build\test_cache\test.dill'), 'kernel')
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'dist\release.zip'), 'published fixture')
    [IO.File]::WriteAllText((Join-Path $fixtureRoot '.dart_tool\old-unused.log'), 'old log')
    (Get-Item -LiteralPath (Join-Path $fixtureRoot '.dart_tool\old-unused.log')).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-7)
    $cleanupScript = Join-Path $fixtureRoot 'tool\maintenance\clean_workspace.ps1'
    & $cleanupScript -IncludeTestCache | Out-Null
    Assert-True (Test-Path -LiteralPath $clean) 'Preview deleted a candidate'
    & $cleanupScript -Apply -IncludeTestCache | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $clean)) 'Clean staging was not removed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'build\test_cache'))) 'Test cache was not removed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot '.dart_tool\old-unused.log'))) 'Old intermediate log was not removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $private 'data\flutter_assets\user.db')) 'Private data was removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $tracked 'mubangumi.exe')) 'Tracked data was removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixtureRoot 'dist\release.zip')) 'Release artifact was removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $outside 'keep.txt')) 'Cleanup followed a junction outside the workspace'
    Write-Output 'Passed 8 workspace cleanup safety checks.'
} finally {
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $testRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $testRoot -Leaf) -notmatch '^mubangumi-cleanup-test-[a-f0-9]{32}$') { throw 'Unsafe test cleanup target' }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
