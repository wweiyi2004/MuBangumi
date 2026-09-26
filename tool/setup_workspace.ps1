#requires -Version 7.0
param([string]$FlutterRoot, [string]$NodePath, [switch]$Flutter, [switch]$Website, [switch]$Python, [switch]$Browsers)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain.ps1')
Push-Location $script:MuRoot
try {
    New-Item -ItemType Directory .dart_tool -Force | Out-Null
    $local = Get-MuLocalTools
    $settings = @{}
    if ($local.flutterRoot) { $settings.flutterRoot = $local.flutterRoot }
    if ($local.node) { $settings.node = $local.node }
    if ($FlutterRoot) { $settings.flutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path }
    if ($NodePath) { $settings.node = (Resolve-Path -LiteralPath $NodePath).Path }
    if ($FlutterRoot) {
        $metadata = Get-Content (Join-Path $settings.flutterRoot 'bin/cache/flutter.version.json') -Raw | ConvertFrom-Json
        if ($metadata.frameworkVersion -ne $script:MuVersions.flutter -or
            $metadata.frameworkRevision -ne $script:MuVersions.flutterFrameworkRevision -or
            $metadata.engineRevision -ne $script:MuVersions.flutterEngineRevision) { throw 'FlutterRoot 版本或引擎与 toolchain.json 不符。' }
    }
    if ($NodePath -and ((& $settings.node --version | Out-String).Trim().TrimStart('v')) -ne $script:MuVersions.node) { throw 'NodePath 版本与 toolchain.json 不符。' }
    $settings | ConvertTo-Json | Set-Content -LiteralPath .dart_tool/toolchain.local.json -Encoding utf8
    if ($Flutter) {
        Invoke-MuFlutter -Arguments @('pub','get','--enforce-lockfile')
        if ($LASTEXITCODE) { throw 'Flutter dependencies failed' }
        Push-Location packages/banjian_server
        try { Invoke-MuDart -Arguments @('pub','get','--enforce-lockfile'); if ($LASTEXITCODE) { throw 'Server dependencies failed' } } finally { Pop-Location }
    }
    if ($Website) {
        Push-Location website
        try { Invoke-MuNpm -Arguments @('ci','--registry=https://registry.npmjs.org'); if ($LASTEXITCODE) { throw 'Website dependencies failed' } } finally { Pop-Location }
    }
    if ($Python) {
        $env:UV_CACHE_DIR = Join-Path $script:MuRoot '.dart_tool/uv-cache'
        $env:UV_PYTHON_INSTALL_DIR = Join-Path $script:MuRoot '.dart_tool/python'
        $requirements = @{recommend_dataset='tool/recommend_dataset/requirements.txt'; semantic_retrieval='tool/semantic_retrieval/requirements.txt'; release_mirror='tool/requirements-mirror.txt'}
        foreach ($project in $requirements.Keys) {
            $directory = '.dart_tool/venvs/' + $project
            if (-not (Test-Path -LiteralPath $directory)) {
                & uv venv --python $script:MuVersions.python.$project $directory
                if ($LASTEXITCODE) { throw "Could not create $project environment" }
            }
            $pythonExecutable = Get-MuPython -Project $project
            & uv pip sync --python $pythonExecutable --require-hashes --index-url https://pypi.org/simple $requirements[$project]
            if ($LASTEXITCODE) { throw "Could not install $project locked dependencies" }
        }
    }
    if ($Browsers) {
        Push-Location website
        try { Invoke-MuNpm -Arguments @('exec','--','playwright','install','chromium'); if ($LASTEXITCODE) { throw 'Browser installation failed' } } finally { Pop-Location }
    }
    Write-Host 'Workspace tool paths and requested dependencies are ready.'
} finally { Pop-Location }
