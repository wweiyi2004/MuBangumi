# Shared by the packager and standalone archive checks. Fail closed for paths
# outside the runtime layout, browser profiles, credentials and SQLite content.
function Assert-WindowsPackageEntry {
    param([Parameter(Mandatory = $true)][string]$Name)
    $normalized = $Name.Replace('\', '/')
    $segments = $normalized.TrimEnd('/').Split('/')
    if ($normalized.StartsWith('/') -or $normalized.Contains(':') -or
        $segments -contains '..' -or $segments -contains '.' -or $segments -contains '') {
        throw "Unsafe archive path: $Name"
    }
    foreach ($segment in $segments) {
        if ($segment -match '(?i)^(\.dart_tool|\.git|\.env(?:\..*)?|EBWebView|.*\.WebView2|Local Storage|Session Storage|IndexedDB|leveldb|Service Worker|Network|Cache|Code Cache|GPUCache|Crashpad)$' -or
            $segment -match '(?i)^(Cookies(?:-.*)?|Login Data(?:-.*)?|History(?:-.*)?|Preferences|Secure Preferences|Local State|Web Data(?:-.*)?|oauth\.local\.json|bangumi_credentials_.*|bangumi_access_token|bangumi_refresh_token|bangumi_website_session_.*)$' -or
            $segment -match '(?i)\.(sqlite|sqlite3|db)(?:[-.].*)?$' -or
            $segment -match '(?i)\.(pem|key|pfx|p12|keystore|symbols|pdb|onnx|npz|npy|safetensors|pt|pth)$') {
            throw "Private runtime data in package: $Name"
        }
    }
    $runtime = $normalized -match '(?i)^(mubangumi\.exe|[^/]+\.dll|native_assets\.json)$' -or
        $normalized -match '(?i)^data/(app\.so|icudtl\.dat)$' -or
        $normalized -match '(?i)^data/flutter_assets(?:/.*)?$' -or
        $normalized -eq 'data/' -or $normalized -eq 'data'
    if (-not $runtime) { throw "Unexpected file outside runtime layout: $Name" }
}

function Assert-NoSqlitePayload {
    param([IO.Stream]$Stream, [string]$Name)
    $header = New-Object byte[] 16
    $read = 0
    while ($read -lt $header.Length) {
        $count = $Stream.Read($header, $read, $header.Length - $read)
        if ($count -eq 0) { break }
        $read += $count
    }
    if ($read -ge 15 -and [Text.Encoding]::ASCII.GetString($header, 0, 15) -eq 'SQLite format 3') {
        throw "SQLite content in package (including renamed files): $Name"
    }
    # Scan runtime binaries too: native diagnostics can embed the build user's
    # absolute paths even when the ZIP contains no private files. Keep a tail to
    # catch ASCII and UTF-16 strings spanning read boundaries. Never echo data.
    $privateRoots = @([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')), $env:USERPROFILE) |
        Where-Object { $_ } | ForEach-Object { $_.Replace('\', '/').ToLowerInvariant() }
    $tail = [Text.Encoding]::ASCII.GetString($header, 0, $read)
    $buffer = New-Object byte[] 65536
    do {
        $count = $Stream.Read($buffer, 0, $buffer.Length)
        $sample = ($tail + [Text.Encoding]::ASCII.GetString($buffer, 0, $count)).Replace("`0", '').Replace('\', '/').ToLowerInvariant()
        if ($sample -match '[a-z]:/+users/+' -or @($privateRoots | Where-Object { $sample.Contains($_) }).Count -gt 0) {
            throw "Personal machine path in package content: $Name"
        }
        $tail = $sample.Substring([Math]::Max(0, $sample.Length - 4096))
    } while ($count -gt 0)
}

function Assert-WindowsPackageDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($entry in Get-ChildItem -LiteralPath $root -Recurse -Force) {
        $relative = $entry.FullName.Substring($root.Length)
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Links are not allowed in packages: $relative"
        }
        Assert-WindowsPackageEntry $relative
        if (-not $entry.PSIsContainer) {
            $stream = [IO.File]::OpenRead($entry.FullName)
            try { Assert-NoSqlitePayload $stream $relative } finally { $stream.Dispose() }
        }
    }
}

function Assert-WindowsPackageArchive {
    param([Parameter(Mandatory = $true)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Path))
    try {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            Assert-WindowsPackageEntry $entry.FullName
            $normalized = $entry.FullName.Replace('\', '/').TrimEnd('/')
            if (-not $names.Add($normalized)) { throw "Duplicate archive entry: $normalized" }
            # Reject Unix symlinks in ZIPs as well as Windows reparse points.
            if (($entry.ExternalAttributes -band 0x400) -ne 0 -or
                (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) {
                throw "Link in archive: $normalized"
            }
            if (-not $entry.FullName.EndsWith('/')) {
                $stream = $entry.Open()
                try { Assert-NoSqlitePayload $stream $normalized } finally { $stream.Dispose() }
            }
        }
        foreach ($required in @('mubangumi.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/shorebird.yaml')) {
            if (-not $names.Contains($required)) { throw "Missing runtime entry: $required" }
        }
    } finally { $zip.Dispose() }
}
