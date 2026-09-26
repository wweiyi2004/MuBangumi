param(
    [ValidateSet('windows', 'apk', 'appbundle')]
    [string]$Target = 'windows',

    [switch]$Shorebird,

    [switch]$Patch,

    [switch]$UniversalApk,

    [string]$ReleaseVersion,

    [string]$FlutterVersion,

    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$BuildName,

    [ValidateRange(1, 2100000000)]
    [int]$BuildNumber,

    [string]$GiteeRepository = $env:GITEE_REPOSITORY,

    [switch]$DryRun,
    [switch]$AllowDirty,
    [string]$VerificationReport,
    [string]$AcceptanceReport
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain.ps1')
if ($UniversalApk -and ($Target -ne 'apk' -or $Patch)) {
    throw '-UniversalApk requires a full APK build.'
}
if (-not $FlutterVersion) { $FlutterVersion = $script:MuVersions.flutter }
if (-not $Patch -and $FlutterVersion -ne $script:MuVersions.flutter) { throw 'FlutterVersion 必须与 tool/toolchain.json 保持一致。' }
if ($GiteeRepository -and ($GiteeRepository -notmatch '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$' -or
    @($GiteeRepository.Split('/') | Where-Object { $_ -in @('.', '..') }).Count -gt 0)) {
    throw 'GiteeRepository 必须是已验证的公开仓库 owner/repository，不要填写完整 URL。'
}
if ($Patch) {
    $Shorebird = $true
    if ($BuildName -or $BuildNumber) {
        throw '补丁使用既有基线版本，不能覆盖 BuildName 或 BuildNumber。'
    }
    if ($ReleaseVersion -notmatch '^\d+\.\d+\.\d+\+\d+$') {
        throw '补丁必须指定完整基线版本，例如 -ReleaseVersion 2.1.0+10。'
    }
}
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$oauthConfigPath = Join-Path $repositoryRoot 'config\oauth.local.json'
$expectedArtifacts = @(switch ($Target) {
    'apk'       {
        if ($Shorebird -or $UniversalApk) {
            'build\app\outputs\flutter-apk\app-release.apk'
        } else {
            foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
                "build\app\outputs\flutter-apk\app-$abi-release.apk"
            }
        }
    }
    'appbundle' { 'build\app\outputs\bundle\release\app-release.aab' }
    'windows'   {
        'build\windows\x64\runner\Release\mubangumi.exe'
        'build\windows\x64\runner\Release\data\app.so'
    }
})
$artifactPaths = @($expectedArtifacts | ForEach-Object { Join-Path $repositoryRoot $_ })
$versionArguments = @()
if ($BuildName) { $versionArguments += "--build-name=$BuildName" }
if ($BuildNumber) { $versionArguments += "--build-number=$BuildNumber" }
if ($GiteeRepository) { $versionArguments += "--dart-define=GITEE_REPOSITORY=$GiteeRepository" }

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
    $clientId.ToLowerInvariant().Contains('your') -or
    $clientSecret.ToLowerInvariant().Contains('your')

if ([string]::IsNullOrWhiteSpace($clientId) -or
    [string]::IsNullOrWhiteSpace($clientSecret) -or
    $hasPlaceholder) {
    throw 'OAuth 配置仍为空或包含示例占位文字，请填写真实凭据后重试。'
}

Push-Location $repositoryRoot
try {
    $versionLine = ((Get-Content pubspec.yaml | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1) -replace '^version:\s*','').Trim()
    if ($versionLine -notmatch '^(\d+\.\d+\.\d+)\+(\d+)$') { throw 'pubspec.yaml 需要明确的版本与构建号。' }
    $effectiveVersion = $(if ($BuildName) { $BuildName } else { $Matches[1] }) + '+' + $(if ($BuildNumber) { $BuildNumber } else { $Matches[2] })
    $recordDirectory = Join-Path $repositoryRoot ('release-symbols\provenance-' + $Target + '-' + [guid]::NewGuid().ToString('N'))
    $provenanceFile = Join-Path $recordDirectory 'provenance.json'
    $kind = if ($DryRun) { 'dry-run' } elseif ($Patch) { 'shorebird-patch' } elseif ($Shorebird) { 'shorebird-release' } else { 'build' }
    $provenanceArguments = @('tool/release_provenance.py','create','--root',$repositoryRoot,'--out',$provenanceFile,
        '--sdk-metadata',(Join-Path (Get-MuFlutterRoot) 'bin/cache/flutter.version.json'),
        '--target',$Target,'--kind',$kind,'--version',$effectiveVersion)
    if ($AllowDirty -or $DryRun) { $provenanceArguments += '--allow-dirty' }
    if ($ReleaseVersion) { $provenanceArguments += @('--baseline',$ReleaseVersion) }
    if ($VerificationReport) { $provenanceArguments += @('--verification',([IO.Path]::GetFullPath($VerificationReport))) }
    if ($AcceptanceReport) { $provenanceArguments += @('--acceptance',([IO.Path]::GetFullPath($AcceptanceReport))) }
    & python @provenanceArguments
    if ($LASTEXITCODE) { throw '发布前检查未通过，尚未运行构建或上传；请查看上方具体原因。' }
    if ($Shorebird) {
        if (-not (Get-Command shorebird -ErrorAction SilentlyContinue)) {
            throw '未找到 Shorebird CLI，请先安装并完成 shorebird login。'
        }
        $platform = if ($Target -eq 'windows') { 'windows' } else { 'android' }
        $arguments = if ($Patch) {
            @('patch', $platform, "--release-version=$ReleaseVersion")
        } else {
            @('release', $platform, "--flutter-version=$FlutterVersion")
        }
        if (-not $Patch -and $Target -eq 'apk') {
            $arguments += '--artifact=apk'
        }
        if ($DryRun) {
            $arguments += '--dry-run'
        } elseif (-not $Patch) {
            foreach ($artifactPath in $artifactPaths) {
                if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
                    Remove-Item -LiteralPath $artifactPath -Force
                }
            }
        }
        # Keep existing Shorebird base/patch compilation options compatible.
        $arguments += @('--', '--no-pub', "--dart-define-from-file=$oauthConfigPath") + $versionArguments
        Write-Host "使用本地 OAuth 配置构建 Shorebird $platform（不会打印密钥）"
        & shorebird @arguments
    } else {
        if ($DryRun) {
            throw '-DryRun 仅适用于 Shorebird 构建。'
        }
        foreach ($artifactPath in $artifactPaths) {
            if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
                Remove-Item -LiteralPath $artifactPath -Force
            }
        }
        # Each build gets a private, unique directory: rebuilding the same version
        # must not overwrite the symbols needed to diagnose an older artifact.
        $symbolDirectory = Join-Path $repositoryRoot ('release-symbols\' + $Target + '-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $symbolDirectory | Out-Null
        $arguments = @('build', $Target, '--release', '--no-pub', '--tree-shake-icons',
            "--split-debug-info=$symbolDirectory", "--dart-define-from-file=$oauthConfigPath") + $versionArguments
        if ($Target -eq 'apk' -and -not $UniversalApk) { $arguments += '--split-per-abi' }
        Write-Host "使用本地 OAuth 配置构建 Flutter $Target release（不会打印密钥）"
        Invoke-MuFlutter -Arguments $arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "构建失败，退出码：$LASTEXITCODE"
    }

    if ($DryRun) {
        & python tool/release_provenance.py finish --root $repositoryRoot --manifest $provenanceFile
        if ($LASTEXITCODE) { throw 'Dry-run 来源记录校验失败。' }
        Write-Host 'Shorebird dry-run 校验通过。'
        return
    }

    if ($Patch) {
        & python tool/release_provenance.py finish --root $repositoryRoot --manifest $provenanceFile
        if ($LASTEXITCODE) { throw '上传后来源记录校验失败，请核对远端结果。' }
        Write-Host "Shorebird 补丁发布完成，基线：$ReleaseVersion。"
        Write-Host "来源记录：$provenanceFile；核对服务器编号后用 release_provenance.py patch-receipt 补全回执。"
        return
    }

    # The pre-build removal above ensures this cannot accept a stale artifact
    # left by an earlier successful build.
    foreach ($artifactPath in $artifactPaths) {
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "构建成功退出，但未找到预期产物：$artifactPath"
        }
        if ((Get-Item -LiteralPath $artifactPath).Length -le 0) {
            throw "构建产物为空文件：$artifactPath"
        }
        Write-Host "产物校验通过：$artifactPath"
    }
    if (-not $Shorebird) {
        $symbols = @(Get-ChildItem -LiteralPath $symbolDirectory -File -Filter '*.symbols')
        if ($symbols.Count -eq 0) { throw "缺少独立调试符号：$symbolDirectory" }
        if (@($symbols | Where-Object { $_.Length -eq 0 }).Count -gt 0) {
            throw "调试符号为空文件：$symbolDirectory"
        }
        if ($Target -eq 'apk') {
            foreach ($platform in @('android-arm', 'android-arm64', 'android-x64')) {
                if ($symbols.Name -notcontains "app.$platform.symbols") {
                    throw "缺少 $platform 调试符号：$symbolDirectory"
                }
            }
        }
        $records = @($artifactPaths | ForEach-Object {
            [ordered]@{ File = [IO.Path]::GetFileName($_); Bytes = (Get-Item -LiteralPath $_).Length; SHA256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
        })
        [ordered]@{
            CreatedUtc = [DateTime]::UtcNow.ToString('o')
            Target = $Target
            Provenance = [IO.Path]::GetRelativePath($symbolDirectory, $provenanceFile)
            Artifacts = $records
            Symbols = @($symbols | ForEach-Object {
                [ordered]@{ File = $_.Name; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
            })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $symbolDirectory 'build.json') -Encoding utf8
        Write-Host "请单独备份调试符号及产物校验记录（不随安装包发布）：$symbolDirectory"
    }
    $finishArguments = @('tool/release_provenance.py','finish','--root',$repositoryRoot,'--manifest',$provenanceFile)
    foreach ($artifactPath in $artifactPaths) { $finishArguments += @('--artifact',$artifactPath) }
    if (-not $Shorebird) { foreach ($symbol in $symbols) { $finishArguments += @('--symbol',$symbol.FullName) } }
    & python @finishArguments
    if ($LASTEXITCODE) { throw '构建来源或产物记录校验失败。' }
    Write-Host "来源与校验记录：$provenanceFile"
} catch {
    $buildFailure = $_
    if ($provenanceFile -and (Test-Path -LiteralPath $provenanceFile)) {
        & python tool/release_provenance.py finish --root $repositoryRoot --manifest $provenanceFile --failed | Out-Null
    }
    throw $buildFailure
} finally {
    Pop-Location
}
