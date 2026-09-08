param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [string]$VisualCppRuntimePath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releasePath = Join-Path $repositoryRoot 'build\windows\x64\runner\Release'
$archivePath = Join-Path $repositoryRoot "dist\MuBangumi-$Version-windows-x64.zip"
if (Test-Path -LiteralPath $archivePath) {
    throw "Archive already exists: $archivePath"
}
foreach ($relative in @('mubangumi.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets\shorebird.yaml')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releasePath $relative) -PathType Leaf)) {
        throw "Missing release runtime file: $relative"
    }
}
$actualVersion = (Get-Item -LiteralPath (Join-Path $releasePath 'mubangumi.exe')).VersionInfo.ProductVersion
if ($actualVersion -notmatch ('^' + [regex]::Escape($Version) + '(?:[.+]|$)')) {
    throw "Executable version $actualVersion does not match $Version"
}

# Running the app in Release can create databases and WebView profiles beside
# the executable. Never archive the whole build output directory.
$stagingPath = Join-Path $repositoryRoot ('.dart_tool\windows-package-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $stagingPath 'data') -Force | Out-Null
Get-ChildItem -LiteralPath $releasePath -File |
    Where-Object { $_.Name -eq 'mubangumi.exe' -or $_.Extension -eq '.dll' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stagingPath }

# Flutter ZIP deployments need the Visual C++ runtime beside the executable.
# Resolve the redistributable directory from the installed build tools rather
# than copying arbitrary DLLs from the system directory.
if ([string]::IsNullOrWhiteSpace($VisualCppRuntimePath)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
        throw 'Cannot locate Visual Studio. Supply -VisualCppRuntimePath with the x64 CRT redistributable directory.'
    }
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($visualStudio)) {
        throw 'Cannot locate Visual C++ build tools.'
    }
    $redistRoot = Join-Path $visualStudio.Trim() 'VC\Redist\MSVC'
    $redistVersion = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $redistVersion) { throw 'No Visual C++ redistributable version found.' }
    $crt = Get-ChildItem -LiteralPath (Join-Path $redistVersion.FullName 'x64') -Directory |
        Where-Object { $_.Name -match '^Microsoft\.VC\d+\.CRT$' } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $crt) { throw 'No x64 Visual C++ runtime directory found.' }
    $VisualCppRuntimePath = $crt.FullName
}
foreach ($requiredRuntime in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $VisualCppRuntimePath $requiredRuntime) -PathType Leaf)) {
        throw "Missing Visual C++ runtime: $requiredRuntime"
    }
}
Get-ChildItem -LiteralPath $VisualCppRuntimePath -File -Filter '*.dll' |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stagingPath }
foreach ($relative in @('app.so', 'icudtl.dat', 'flutter_assets')) {
    Copy-Item -LiteralPath (Join-Path $releasePath "data\$relative") -Destination (Join-Path $stagingPath 'data') -Recurse
}
# A legacy root manifest may still contain absolute paths from a debug build.
# Reuse the current release manifest, whose DLL names resolve in this bundle.
$nativeManifest = Join-Path $releasePath 'data\flutter_assets\NativeAssetsManifest.json'
if (Test-Path -LiteralPath $nativeManifest -PathType Leaf) {
    Copy-Item -LiteralPath $nativeManifest -Destination (Join-Path $stagingPath 'native_assets.json')
}
$privateFiles = Get-ChildItem -LiteralPath $stagingPath -Recurse -File |
    Where-Object { $_.Name -match '\.(sqlite|sqlite3|db)(-|$)' -or $_.Name -eq 'oauth.local.json' }
if ($privateFiles) { throw 'Refusing to package local database or credential files.' }
New-Item -ItemType Directory -Path (Split-Path $archivePath -Parent) -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingPath, $archivePath)
Write-Host "Packaged runtime files: $archivePath"
