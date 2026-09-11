$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\windows_package_safety.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('mubangumi-package-test-' + [guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$passed = 0

function New-FixtureArchive {
    param([string]$Path, [string]$ExtraName, [byte[]]$ExtraBytes)
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in @('mubangumi.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/shorebird.yaml', 'webview_flutter_windows_plugin.dll', 'flutter_secure_storage_windows_plugin.dll')) {
            $entry = $zip.CreateEntry($name)
            $stream = $entry.Open()
            try { $stream.WriteByte(0) } finally { $stream.Dispose() }
        }
        if ($ExtraName) {
            $entry = $zip.CreateEntry($ExtraName)
            if ($ExtraBytes) {
                $stream = $entry.Open()
                try { $stream.Write($ExtraBytes, 0, $ExtraBytes.Length) } finally { $stream.Dispose() }
            }
        }
    } finally { $zip.Dispose() }
}

try {
    $clean = Join-Path $testRoot 'clean.zip'
    New-FixtureArchive $clean
    Assert-WindowsPackageArchive $clean
    $passed++
    foreach ($name in @(
        '.dart_tool/sqflite_common_ffi/databases/mubangumi.sqlite',
        'data/flutter_assets/nested/user.db-wal',
        'data/flutter_assets/EBWebView/Default/Cookies',
        'data/flutter_assets/Local State',
        'data/flutter_assets/Local Storage/leveldb/000001.log',
        'data/flutter_assets/oauth.local.json',
        'data/flutter_assets/bangumi_credentials_v2',
        '../data/flutter_assets/file.txt',
        'unexpected.txt',
        'DATA/APP.SO'
    )) {
        $archive = Join-Path $testRoot ('bad-' + $passed + '.zip')
        New-FixtureArchive $archive $name
        $rejected = $false
        try { Assert-WindowsPackageArchive $archive } catch { $rejected = $true }
        if (-not $rejected) { throw "Unsafe archive passed: $name" }
        $passed++
    }
    $renamed = Join-Path $testRoot 'renamed.zip'
    New-FixtureArchive $renamed 'data/flutter_assets/innocent.bin' ([Text.Encoding]::ASCII.GetBytes("SQLite format 3`0"))
    $rejected = $false
    try { Assert-WindowsPackageArchive $renamed } catch { $rejected = $true }
    if (-not $rejected) { throw 'Renamed SQLite database passed' }
    $passed++
    $unpacked = Join-Path $testRoot 'staging'
    [IO.Compression.ZipFile]::ExtractToDirectory($clean, $unpacked)
    Assert-WindowsPackageDirectory $unpacked
    [IO.File]::WriteAllText((Join-Path $unpacked 'data\flutter_assets\Cookies'), 'test-only')
    $rejected = $false
    try { Assert-WindowsPackageDirectory $unpacked } catch { $rejected = $true }
    if (-not $rejected) { throw 'Staging Cookie file passed' }
    $passed++
    Write-Output "Passed $passed Windows package safety checks."
} finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $testRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path $testRoot -Leaf).StartsWith('mubangumi-package-test-')) {
        throw 'Refusing cleanup outside the generated test directory'
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
