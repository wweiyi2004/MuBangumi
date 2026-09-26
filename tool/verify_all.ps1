#requires -Version 7.0
param(
    [ValidateSet('Quick','Full')][string]$Mode = 'Quick',
    [ValidateSet('flutter','server','website','python','tools')][string[]]$Areas = @('flutter','server','website','python','tools'),
    [string]$DeviceId,
    [switch]$WindowsSmoke
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain.ps1')
if ($WindowsSmoke -and ($Mode -ne 'Full' -or -not $IsWindows -or $Areas -notcontains 'flutter')) {
    throw '-WindowsSmoke requires Full Flutter verification on Windows.'
}
$resultDirectory = Join-Path $script:MuRoot ('.dart_tool/verification/' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
$checks = [Collections.Generic.List[object]]::new()
$deferred = [Collections.Generic.List[string]]::new()
function Check([string]$Name, [scriptblock]$Action) {
    $log = Join-Path $resultDirectory ($Name + '.log')
    Write-Host "Checking $Name..."
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $global:LASTEXITCODE = 0
    try {
        & $Action *> $log
        if ($LASTEXITCODE -ne 0) { throw "Command exited with $LASTEXITCODE" }
        $checks.Add(@{name=$Name;status='passed';seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);log=$log})
    } catch {
        $_.Exception.Message | Add-Content -LiteralPath $log
        $checks.Add(@{name=$Name;status='failed';seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);log=$log})
        Write-Warning "$Name failed. See $log"
    }
}
Push-Location $script:MuRoot
try {
    $sourceBefore = (& python tool/release_provenance.py identity --root $script:MuRoot | ConvertFrom-Json)
    if ($LASTEXITCODE) { throw 'Cannot identify source content' }
    Check 'toolchain-files' { python tool/check_toolchain.py }
    if ($Areas -contains 'flutter') {
        Check 'flutter-analyze' { Invoke-MuFlutter -Arguments @('analyze','--no-pub') }
        Check 'flutter-tests' { Invoke-MuFlutter -Arguments @('test','--no-pub','--reporter','expanded') }
        if ($Mode -eq 'Full') {
            if ($DeviceId) { Check 'device-smoke' { Invoke-MuFlutter -Arguments @('test','--no-pub','integration_test/platform_smoke_test.dart','-d',$DeviceId) } }
            if (-not $DeviceId -or $DeviceId -in @('windows','linux','macos','chrome','edge')) {
                $deferred.Add('Android/iOS device smoke not run: requires a dedicated mobile device or emulator')
            }
            if ($WindowsSmoke) {
                if ($DeviceId -ne 'windows') {
                    Check 'windows-storage-smoke' { Invoke-MuFlutter -Arguments @('test','--no-pub','integration_test/platform_smoke_test.dart','-d','windows') }
                }
                Check 'windows-webview-smoke' { Invoke-MuFlutter -Arguments @('test','--no-pub','integration_test/windows_webview_smoke_test.dart','-d','windows') }
            } elseif ($IsWindows) {
                $deferred.Add('Windows WebView smoke not run: use -WindowsSmoke for the local WebView check')
                if ($DeviceId -ne 'windows') {
                    $deferred.Add('Windows secure storage/SQLite smoke not run: use -WindowsSmoke')
                }
            }
            # Integration tests build a separate entry point into the same Debug
            # output. Restore normal application artifacts after all smoke runs.
            if ($IsWindows) { Check 'windows-build' { Invoke-MuFlutter -Arguments @('build','windows','--debug','--no-pub') } }
            Check 'android-build' { Invoke-MuFlutter -Arguments @('build','apk','--debug','--no-pub','--target-platform','android-arm64') }
            if ($IsMacOS) { Check 'ios-build' { Invoke-MuFlutter -Arguments @('build','ios','--simulator','--debug','--no-codesign','--no-pub') } }
            else { $deferred.Add('iOS simulator build not run: requires macOS; CI configuration is not execution evidence') }
            $deferred.Add('Real-account acceptance, native file exchange, reminders and update installation are separate manual checks; automated smoke does not certify them')
        }
    }
    if ($Areas -contains 'server') {
        Push-Location packages/banjian_server
        try {
            Check 'server-analyze' { Invoke-MuDart -Arguments @('analyze') }
            Check 'server-tests' { Invoke-MuDart -Arguments @('test') }
            if ($Mode -eq 'Full') { Check 'server-bundle' { Invoke-MuDart -Arguments @('build','cli','--target','bin/server.dart','-o',(Join-Path $resultDirectory 'server-build')) } }
        } finally { Pop-Location }
        Check 'browser-protocol' { & (Get-MuNode) packages/banjian_server/test/room_protocol_test.cjs }
    }
    if ($Areas -contains 'website') {
        Push-Location website
        try {
            Check 'website-check' { Invoke-MuNpm -Arguments @('run','check') }
            Check 'website-audit' { Invoke-MuNpm -Arguments @('run','audit:security') }
            if ($Mode -eq 'Full') { Check 'website-browser' { Invoke-MuNpm -Arguments @('run','test:browser') } }
        } finally { Pop-Location }
    }
    if ($Areas -contains 'python') {
        Check 'dataset-tests' { & (Get-MuPython recommend_dataset) -m pytest tool/recommend_dataset/tests -q }
        Check 'semantic-tests' { & (Get-MuPython semantic_retrieval) -m pytest tool/semantic_retrieval/tests -q }
        Check 'mirror-tests' { & (Get-MuPython release_mirror) -m unittest discover -s tool/tests -p mirror_release_test.py }
    }
    if ($Areas -contains 'tools') {
        Check 'architecture' { python tool/verify_architecture.py --self-test }
        foreach ($name in @('windows_package_safety','release_build','workspace_cleanup')) {
            if (-not $IsWindows -and $name -eq 'workspace_cleanup') { continue }
            Check $name { & pwsh -NoProfile -File "tool/tests/${name}_test.ps1" }
        }
        Check 'repository-privacy' { & pwsh -NoProfile -File tool/verify_repository_privacy.ps1 }
        Check 'repository-privacy-tests' { python -m unittest discover -s tool/tests -p repository_privacy_test.py }
        Check 'provenance-tests' { python -m unittest discover -s tool/tests -p release_provenance_test.py }
    }
} finally {
    $sourceAfter = (& python (Join-Path $script:MuRoot 'tool/release_provenance.py') identity --root $script:MuRoot | ConvertFrom-Json)
    if ($LASTEXITCODE -or $sourceBefore.fingerprint -ne $sourceAfter.fingerprint) {
        $checks.Add(@{name='source-unchanged';status='failed';log='Source changed during verification; rerun after edits finish'})
    }
    Pop-Location
    $failed = @($checks | Where-Object status -eq 'failed').Count
    @{schema=1;createdUtc=[DateTime]::UtcNow.ToString('o');mode=$Mode;source=$sourceAfter;passed=($failed -eq 0);checks=@($checks);deferred=@($deferred)} |
        ConvertTo-Json -Depth 6 | Set-Content (Join-Path $resultDirectory 'results.json') -Encoding utf8
}
Write-Host "Verification report: $(Join-Path $resultDirectory 'results.json')"
if ($failed) { exit 1 }
