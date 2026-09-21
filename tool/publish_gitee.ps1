param(
    [string]$Tag,
    [string]$GiteeRepository = 'wweiyi/mu-bangumi',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$venvDirectory = Join-Path $repositoryRoot '.dart_tool\mirror-venv'
$mirrorPython = Join-Path $venvDirectory 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $mirrorPython -PathType Leaf)) {
    & python -m venv $venvDirectory
    if ($LASTEXITCODE -ne 0) { throw '创建发布工具环境失败，请确认 Python 3.10+ 可用。' }
}
& $mirrorPython -m pip install -r (Join-Path $PSScriptRoot 'requirements-mirror.txt')
if ($LASTEXITCODE -ne 0) { throw '安装发布工具依赖失败。' }

$previousToken = $env:GITEE_TOKEN
$secureToken = $null
try {
    if (-not $DryRun -and [string]::IsNullOrWhiteSpace($previousToken)) {
        $secureToken = Read-Host '请粘贴 Gitee 私人令牌（不会显示或保存到文件），然后按 Enter' -AsSecureString
        $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        try {
            $env:GITEE_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
        }
    }
    $arguments = @((Join-Path $PSScriptRoot 'mirror_release.py'), '--repository', $GiteeRepository)
    if ($Tag) { $arguments += @('--tag', $Tag) }
    if ($DryRun) { $arguments += '--dry-run' }
    & $mirrorPython @arguments
    if ($LASTEXITCODE -ne 0) { throw '发布未完成；上方日志包含具体原因。已存在的同名附件会在下次运行时校验复用。' }
} finally {
    $env:GITEE_TOKEN = $previousToken
    if ($null -ne $secureToken) { $secureToken.Dispose() }
}
