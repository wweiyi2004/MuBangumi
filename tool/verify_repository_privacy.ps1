$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repositoryRoot
try {
    $tracked = & git -c core.quotepath=false ls-files
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked files.' }
    $violations = @()
    foreach ($file in $tracked) {
        $name = $file.Replace('\', '/')
        $privatePath =
            $name -match '(?i)(^|/)(\.dart_tool|EBWebView|[^/]*\.WebView2)/' -or
            $name -match '(?i)(^|/)(oauth\.local\.json|key\.properties|local\.properties|Cookies(?:-.*)?|Login Data(?:-.*)?|Local State)$' -or
            ($name -match '(?i)(^|/)\.env(?:\..*)?$' -and $name -notmatch '(?i)\.example$') -or
            $name -match '(?i)\.(sqlite|sqlite3|db)(?:[-.].*)?$' -or
            $name -match '(?i)\.(jks|keystore|p12|pfx|pem|key)$' -or
            $name -match '(?i)^(build|dist)/'
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
        }
    }
    if ($violations.Count -gt 0) {
        throw ("Private configuration or runtime data is tracked by Git:`n" + ($violations -join "`n"))
    }
    Write-Host "Repository privacy check passed ($($tracked.Count) tracked files)."
    # This is a file/layout guard, not a general secret scanner. In particular,
    # it cannot identify arbitrary credentials pasted into source code.
} finally { Pop-Location }
