#requires -Version 7.0
param([switch]$Upgrade)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain.ps1')
$env:UV_CACHE_DIR = Join-Path $script:MuRoot '.dart_tool/uv-cache'
$projects = @{recommend_dataset='tool/recommend_dataset/requirements'; semantic_retrieval='tool/semantic_retrieval/requirements'; release_mirror='tool/requirements-mirror'}
Push-Location $script:MuRoot
try {
    foreach ($project in $projects.Keys) {
        $base = $projects[$project]
        $arguments = @('pip','compile',"$base.in",'--python-version',$script:MuVersions.python.$project,'--universal','--generate-hashes','--no-annotate','--no-emit-index-url','--index-url','https://pypi.org/simple','--output-file',"$base.txt",'--custom-compile-command','pwsh -File tool/lock_python.ps1')
        if ($Upgrade) { $arguments += '--upgrade' } else { $arguments += @('--constraint',"$base.txt") }
        & uv @arguments
        if ($LASTEXITCODE) { throw "Failed to lock $project" }
    }
} finally { Pop-Location }
