$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repositoryRoot
try {
    # Include pending new files so the same guard works before staging and in CI.
    $tracked = @(& git -c core.quotepath=false ls-files --cached --others --exclude-standard | Sort-Object -Unique)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate publishable files.' }
    $violations = @()
    foreach ($file in $tracked) {
        $name = $file.Replace('\', '/')
        $privatePath =
            $name -match '(?i)(^|/)(\.dart_tool|EBWebView|[^/]*\.WebView2)/' -or
            $name -match '(?i)(^|/)(oauth\.local\.json|key\.properties|local\.properties|Cookies(?:-.*)?|Login Data(?:-.*)?|Local State)$' -or
            $name -match '(?i)(^|/)(bangumi_credentials_[^/]+\.json|website_session(?:_[^/]+)?\.json|session\.json|cleanup-state\.json|gitee_credentials(?:_[^/]+)?\.json)$' -or
            ($name -match '(?i)(^|/)\.env(?:\..*)?$' -and $name -notmatch '(?i)\.example$') -or
            $name -match '(?i)\.(sqlite|sqlite3|db)(?:[-.].*)?$' -or
            $name -match '(?i)\.(jks|keystore|p12|pfx|pem|key)$' -or
            $name -match '(?i)\.(symbols|pdb|npz|npy|onnx|safetensors|pt|pth)$' -or
            $name -match '(?i)^(build|dist|release-symbols)/'
        if ($privatePath) {
            $violations += $name
            continue
        }
        $path = Join-Path $repositoryRoot $file
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $stream = [IO.File]::OpenRead($path)
            try {
                $header = New-Object byte[] 16
                $read = $stream.Read($header, 0, $header.Length)
                if ($read -ge 15 -and [Text.Encoding]::ASCII.GetString($header, 0, 15) -eq 'SQLite format 3') {
                    $violations += "$name (SQLite content)"
                }
            } finally { $stream.Dispose() }
            if ([IO.Path]::GetExtension($path) -match '^\.(md|txt|json|ya?ml|dart|py|ps1|[cm]?js|tsx?|kt|kts|xml|html|css|toml|ini|config)$' -or
                [IO.Path]::GetFileName($path) -in @('.env.example', '.gitignore', '.fvmrc')) {
                $content = [IO.File]::ReadAllText($path)
                if ($content -match '(?i)[a-z]:[\\/]+Users[\\/]' -or
                    $content.Replace('\', '/').IndexOf($repositoryRoot.Replace('\', '/'), [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $violations += "$name (personal machine path)"
                }
                if ($content -match '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)') {
                    $violations += "$name (credential signature)"
                }
                $credentialValues = [regex]::Matches($content, '(?i)"(?:access_token|refresh_token|client_secret|GITEE_TOKEN|BGM_CLIENT_SECRET)"\s*:\s*"([A-Za-z0-9_+/=-]{24,})"')
                foreach ($candidate in $credentialValues) {
                    if ($candidate.Groups[1].Value -notmatch '(?i)^(?:synthetic|fixture|example|sample|test[-_]|replace|your[-_])') {
                        $violations += "$name (account credential value)"
                        break
                    }
                }
            }
        }
    }
    if ($violations.Count -gt 0) {
        throw ("Private configuration or data in publishable files:`n" + ($violations -join "`n"))
    }
    Write-Host "Repository privacy check passed ($($tracked.Count) publishable files)."
    # Fixed signatures complement the file/layout guard, not a general secret
    # scanner. Arbitrary credentials still need a separate publication review.
} finally { Pop-Location }
