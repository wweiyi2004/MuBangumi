param([switch]$Apply, [switch]$IncludeTestCache)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $workspace 'pubspec.yaml'))) { throw 'Not the MuBangumi workspace' }
. (Join-Path $workspace 'tool\windows_package_safety.ps1')

# All candidates come from this allowlist. Never delete build/, dist/, SDKs,
# environments, symbols, credentials, databases, or arbitrary untracked files.
$candidates = [Collections.Generic.List[object]]::new()
function Add-Candidate([string]$Relative, [string]$Reason) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $Relative))
    if (Test-Path -LiteralPath $path) { $candidates.Add([pscustomobject]@{ Path=$path; Relative=$Relative.Replace('\','/'); Reason=$Reason }) }
}
Get-ChildItem -LiteralPath (Join-Path $workspace '.dart_tool') -Directory -ErrorAction SilentlyContinue |
    Where-Object Name -match '^windows-package-[a-f0-9]{32}$' |
    ForEach-Object { Add-Candidate ('.dart_tool/' + $_.Name) 'Windows packaging staging copy' }
Add-Candidate '.pytest_cache' 'Regenerable pytest cache'
if ($IncludeTestCache) { Add-Candidate 'build/test_cache' 'Regenerable Flutter test kernels' }

$references = @(Get-ChildItem -LiteralPath (Join-Path $workspace 'docs') -Recurse -File -Filter '*.md' |
    ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
$cutoff = [DateTime]::UtcNow.AddDays(-2)
Get-ChildItem -LiteralPath (Join-Path $workspace '.dart_tool') -File -Filter '*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTimeUtc -lt $cutoff -and $_.Name -notmatch '^(release|shorebird|semantic)' -and -not $references.Contains($_.Name) } |
    ForEach-Object { Add-Candidate ('.dart_tool/' + $_.Name) 'Old unreferenced intermediate log' }

function Assert-Contained([string]$Target) {
    $full = [IO.Path]::GetFullPath($Target)
    if (-not $full.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Cleanup target escapes the workspace'
    }
    $cursor = Get-Item -LiteralPath $full -Force
    while ($cursor -and $cursor.FullName -ne $workspace) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cleanup never follows links' }
        $cursor = Get-Item -LiteralPath (Split-Path -Parent $cursor.FullName) -Force
    }
}

$tracked = @(& git -C $workspace -c core.quotepath=false ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Cannot establish tracked-file protection' }
$processes = @(Get-CimInstance Win32_Process)
$records = @()
foreach ($candidate in $candidates) {
    try {
        Assert-Contained $candidate.Path
        if ($tracked | Where-Object { $_ -eq $candidate.Relative -or $_.StartsWith($candidate.Relative + '/') }) { throw 'Contains tracked files' }
        if ($processes | Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -eq $candidate.Path -or $_.ExecutablePath.StartsWith($candidate.Path + '\', [StringComparison]::OrdinalIgnoreCase)) }) { throw 'Used by a running executable' }
        if ($candidate.Relative -eq 'build/test_cache' -and ($processes | Where-Object Name -eq 'flutter_tester.exe')) { throw 'Flutter tests are running' }
        $item = Get-Item -LiteralPath $candidate.Path -Force
        $entries = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $candidate.Path -Recurse -Force) } else { @($item) }
        if ($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Contains links' }
        if ($candidate.Relative -like '.dart_tool/windows-package-*') { Assert-WindowsPackageDirectory $candidate.Path }
        $files = @($entries | Where-Object { -not $_.PSIsContainer })
        if ($files | Where-Object { $_.Name -match '(?i)\.(sqlite|sqlite3|db)(?:[-.].*)?$|\.(jks|keystore|pem|key|symbols)$' }) { throw 'Contains a database, credential, or symbol file' }
        foreach ($file in $files) {
            $stream = [IO.File]::OpenRead($file.FullName)
            try { Assert-NoSqlitePayload $stream $file.Name } finally { $stream.Dispose() }
        }
        if ($candidate.Relative -eq 'build/test_cache' -and ($files | Where-Object Extension -ne '.dill')) { throw 'Unexpected content in test cache' }
        $bytes = [long](($files | Measure-Object Length -Sum).Sum)
        if ($Apply) {
            # Verify the absolute target again immediately before deletion.
            Assert-Contained $candidate.Path
            Remove-Item -LiteralPath $candidate.Path -Recurse -Force
        }
        $records += [pscustomobject]@{ Path=$candidate.Relative; Reason=$candidate.Reason; Files=$files.Count; Bytes=$bytes; Result=$(if($Apply){'removed'}else{'preview'}) }
    } catch {
        $records += [pscustomobject]@{ Path=$candidate.Relative; Reason=$candidate.Reason; Files=0; Bytes=0; Result='skipped'; Detail=$_.Exception.Message }
    }
}
$manifest = Join-Path $workspace ('.dart_tool/cleanup-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.json')
ConvertTo-Json -InputObject @($records) -Depth 4 | Set-Content -LiteralPath $manifest -Encoding utf8
$eligible = @($records | Where-Object Result -ne 'skipped')
[pscustomobject]@{ Mode=$(if($Apply){'applied'}else{'preview'}); Targets=$eligible.Count; Files=[long](($eligible | Measure-Object Files -Sum).Sum); MiB=[math]::Round(($eligible | Measure-Object Bytes -Sum).Sum / 1MB, 2); Skipped=@($records | Where-Object Result -eq 'skipped').Count; Manifest=$manifest } | Format-List
