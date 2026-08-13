param(
    [ValidateSet('windows', 'apk', 'appbundle')]
    [string]$Target = 'windows',

    [switch]$Shorebird,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$oauthConfigPath = Join-Path $repositoryRoot 'config\oauth.local.json'

if (-not (Test-Path -LiteralPath $oauthConfigPath -PathType Leaf)) {
    throw @"
缺少本地 OAuth 配置：$oauthConfigPath
请先执行：
  Copy-Item config\oauth.local.json.example config\oauth.local.json
然后填写真实的 BGM_CLIENT_ID 和 BGM_CLIENT_SECRET。
该文件已被 Git 忽略。
"@
}

try {
    $oauthConfig = Get-Content -LiteralPath $oauthConfigPath -Raw | ConvertFrom-Json
} catch {
    throw "OAuth 配置不是有效 JSON：$oauthConfigPath"
}

$clientId = [string]$oauthConfig.BGM_CLIENT_ID
$clientSecret = [string]$oauthConfig.BGM_CLIENT_SECRET
$hasPlaceholder =
    $clientId.Contains('填写') -or
    $clientSecret.Contains('填写') -or
    $clientId.Contains('your', [System.StringComparison]::OrdinalIgnoreCase) -or
    $clientSecret.Contains('your', [System.StringComparison]::OrdinalIgnoreCase)

if ([string]::IsNullOrWhiteSpace($clientId) -or
    [string]::IsNullOrWhiteSpace($clientSecret) -or
    $hasPlaceholder) {
    throw 'OAuth 配置仍为空或包含示例占位文字，请填写真实凭据后重试。'
}

Push-Location $repositoryRoot
try {
    if ($Shorebird) {
        if (-not (Get-Command shorebird -ErrorAction SilentlyContinue)) {
            throw '未找到 Shorebird CLI，请先安装并完成 shorebird login。'
        }
        $platform = if ($Target -eq 'windows') { 'windows' } else { 'android' }
        $arguments = @('release', $platform)
        if ($Target -eq 'apk') {
            $arguments += '--artifact=apk'
        }
        if ($DryRun) {
            $arguments += '--dry-run'
        }
        $arguments += @('--', "--dart-define-from-file=$oauthConfigPath")
        Write-Host "使用本地 OAuth 配置构建 Shorebird $platform release（不会打印密钥）"
        & shorebird @arguments
    } else {
        if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
            throw '未找到 Flutter CLI。'
        }
        if ($DryRun) {
            throw '-DryRun 仅适用于 Shorebird 构建。'
        }
        Write-Host "使用本地 OAuth 配置构建 Flutter $Target release（不会打印密钥）"
        & flutter build $Target --release "--dart-define-from-file=$oauthConfigPath"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "构建失败，退出码：$LASTEXITCODE"
    }
} finally {
    Pop-Location
}
