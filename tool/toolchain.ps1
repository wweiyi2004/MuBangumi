#requires -Version 7.0
$script:MuRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:MuVersions = Get-Content (Join-Path $script:MuRoot 'tool/toolchain.json') -Raw | ConvertFrom-Json
function Get-MuLocalTools {
    $file = Join-Path $script:MuRoot '.dart_tool/toolchain.local.json'
    if (Test-Path -LiteralPath $file) { return Get-Content -LiteralPath $file -Raw | ConvertFrom-Json }
    return @{}
}
function Get-MuFlutterRoot {
    $local = Get-MuLocalTools
    $command = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $paths = @($env:MUBANGUMI_FLUTTER_ROOT, $local.flutterRoot, (Join-Path $script:MuRoot '.fvm/flutter_sdk'))
    if ($command) { $paths += [IO.Path]::GetFullPath((Join-Path (Split-Path $command.Source -Parent) '..')) }
    foreach ($candidate in $paths) {
        if (-not $candidate) { continue }
        $metadata = Join-Path $candidate 'bin/cache/flutter.version.json'
        if (-not (Test-Path -LiteralPath $metadata)) { continue }
        $version = Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
        if ($version.frameworkVersion -eq $script:MuVersions.flutter -and
            $version.frameworkRevision -eq $script:MuVersions.flutterFrameworkRevision -and
            $version.engineRevision -eq $script:MuVersions.flutterEngineRevision) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw "需要官方 Flutter $($script:MuVersions.flutter) 及 toolchain.json 指定引擎，不能用同名 Shorebird fork 代替普通构建 SDK。使用 FVM 安装指定版本，或配置 MUBANGUMI_FLUTTER_ROOT。"
}
function Invoke-MuFlutter {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $sdk = Get-MuFlutterRoot
    $dart = Join-Path $sdk ('bin/cache/dart-sdk/bin/dart' + $(if ($IsWindows) { '.exe' } else { '' }))
    & $dart (Join-Path $sdk 'bin/cache/flutter_tools.snapshot') --no-version-check @Arguments
}
function Invoke-MuDart {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $sdk = Get-MuFlutterRoot
    & (Join-Path $sdk ('bin/cache/dart-sdk/bin/dart' + $(if ($IsWindows) { '.exe' } else { '' }))) @Arguments
}
function Get-MuNode {
    $local = Get-MuLocalTools
    $command = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    foreach ($candidate in @($env:MUBANGUMI_NODE, $local.node, $command.Source)) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate)) { continue }
        $version = (& $candidate --version | Out-String).Trim().TrimStart('v')
        if ($LASTEXITCODE -eq 0 -and $version -eq $script:MuVersions.node) { return $candidate }
    }
    throw "需要 Node $($script:MuVersions.node)。安装 website/.node-version 指定版本，或用 tool/setup_workspace.ps1 -NodePath 指定已有运行时。"
}
function Invoke-MuNpm {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $node = Get-MuNode
    $npm = Get-Command npm -CommandType Application,ExternalScript -ErrorAction Stop | Select-Object -First 1
    $cli = Join-Path (Split-Path $npm.Source -Parent) 'node_modules/npm/bin/npm-cli.js'
    if (-not (Test-Path -LiteralPath $cli)) {
        $file = Get-Item -LiteralPath $npm.Source
        $cli = if ($file.LinkType) { $file.ResolveLinkTarget($true).FullName } else { $file.FullName }
    }
    $previousPath = $env:PATH
    $previousBrowserCache = $env:PLAYWRIGHT_BROWSERS_PATH
    $shimDirectory = $null
    try {
        $env:PATH = (Split-Path $node -Parent) + [IO.Path]::PathSeparator + $previousPath
        if ($IsWindows) {
            # Installed npm.cmd prefers its adjacent global node.exe over PATH.
            # Keep recursive npm/npx lifecycle calls on the pinned runtime too.
            $shimDirectory = Join-Path $script:MuRoot ('.dart_tool/npm-shims/' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $shimDirectory -Force | Out-Null
            foreach ($entry in @('npm', 'npx')) {
                $entryCli = Join-Path (Split-Path $cli -Parent) ($entry + '-cli.js')
                if (-not (Test-Path -LiteralPath $entryCli)) { throw "Missing $entry CLI: $entryCli" }
                $nodeArgument = $node.Replace('%', '%%')
                $cliArgument = $entryCli.Replace('%', '%%')
                $shim = "@echo off`r`nsetlocal DisableDelayedExpansion`r`n`"$nodeArgument`" `"$cliArgument`" %*`r`nexit /b %errorlevel%`r`n"
                Set-Content -LiteralPath (Join-Path $shimDirectory ($entry + '.cmd')) -Value $shim -Encoding utf8NoBOM
            }
            $env:PATH = $shimDirectory + [IO.Path]::PathSeparator + $env:PATH
        }
        if (-not $env:PLAYWRIGHT_BROWSERS_PATH) { $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $script:MuRoot '.dart_tool/playwright' }
        & $node $cli @Arguments
    } finally {
        $env:PATH = $previousPath
        $env:PLAYWRIGHT_BROWSERS_PATH = $previousBrowserCache
        if ($shimDirectory) {
            foreach ($entry in @('npm', 'npx')) {
                $shimFile = Join-Path $shimDirectory ($entry + '.cmd')
                if (Test-Path -LiteralPath $shimFile) { Remove-Item -LiteralPath $shimFile -Force }
            }
            Remove-Item -LiteralPath $shimDirectory -Force
        }
    }
}
function Get-MuPython {
    param([ValidateSet('recommend_dataset','semantic_retrieval','release_mirror')][string]$Project)
    $path = Join-Path $script:MuRoot ('.dart_tool/venvs/' + $Project + $(if ($IsWindows) { '/Scripts/python.exe' } else { '/bin/python' }))
    if (-not (Test-Path -LiteralPath $path)) { throw "缺少 $Project 环境，请先运行 tool/setup_workspace.ps1 -Python。" }
    $version = (& $path -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' | Out-String).Trim()
    if ($version -ne $script:MuVersions.python.$Project) { throw "$Project Python 版本不符：$version" }
    return $path
}
