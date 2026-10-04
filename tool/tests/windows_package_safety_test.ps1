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
    $knownDigest = '0177c65f93ce210580d8855ee69a4a46b36df97a7ac52c1f4ae1b731a812beee'
    $publicPrefixes = @(Get-PublicRuntimeBuildPrefixes 'flutter_windows.dll' $knownDigest)
    if ($publicPrefixes.Count -ne 1) { throw 'Known official runtime was not identified' }
    if (@(Get-PublicRuntimeBuildPrefixes 'native_plugin.dll' $knownDigest).Count -ne 0 -or
        @(Get-PublicRuntimeBuildPrefixes 'flutter_windows.dll' ('0' * 64)).Count -ne 0) {
        throw 'Runtime exception accepted a different file or digest'
    }
    $passed++
    foreach ($encoding in @([Text.Encoding]::ASCII, [Text.Encoding]::Unicode)) {
        foreach ($prefixLength in @(0, 65543)) {
            $publicPath = 'C:' + '/Users/' + 'runneradmin/.cargo/registry/src/example/src/lib.rs'
            $payload = [byte[]]::new($prefixLength) + $encoding.GetBytes($publicPath)
            $stream = [IO.MemoryStream]::new($payload)
            try { Assert-NoSqlitePayload $stream 'flutter_windows.dll' $publicPrefixes } finally { $stream.Dispose() }
            foreach ($privatePath in @(('C:' + '/Users/' + 'synthetic-person/source.cpp'), (Join-Path $env:USERPROFILE 'private/source.cpp'))) {
                $payload = [byte[]]::new($prefixLength) + $encoding.GetBytes($publicPath + ' ' + $privatePath)
                $stream = [IO.MemoryStream]::new($payload)
                $rejected = $false
                try { Assert-NoSqlitePayload $stream 'flutter_windows.dll' $publicPrefixes } catch { $rejected = $true }
                finally { $stream.Dispose() }
                if (-not $rejected) { throw 'Public SDK diagnostics masked a private path' }
            }
            $passed++
        }
    }
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
        'data/flutter_assets/app.windows.symbols',
        'data/flutter_assets/model.onnx',
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
    foreach ($encoding in @([Text.Encoding]::ASCII, [Text.Encoding]::Unicode)) {
        foreach ($prefixLength in @(0, 65543)) {
            $archive = Join-Path $testRoot ('path-' + $passed + '.zip')
            $privatePath = 'C:' + '/Users/' + 'synthetic-person/source.cpp'
            $payload = [byte[]]::new($prefixLength) + $encoding.GetBytes($privatePath)
            New-FixtureArchive $archive 'native_plugin.dll' $payload
            $rejected = $false
            try { Assert-WindowsPackageArchive $archive } catch {
                $rejected = $true
                if ($_.Exception.Message.Contains($privatePath)) { throw 'Private path echoed in diagnostic' }
            }
            if (-not $rejected) { throw 'Binary with an embedded personal path passed' }
            $passed++
        }
    }
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
