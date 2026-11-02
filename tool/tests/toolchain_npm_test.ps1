#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../toolchain.ps1')
$fixtureDirectory = Join-Path $script:MuRoot ('.dart_tool/toolchain-npm-tests/' + [guid]::NewGuid().ToString('N'))
$originalPath = $env:PATH
$originalBrowserCache = $env:PLAYWRIGHT_BROWSERS_PATH
New-Item -ItemType Directory -Path $fixtureDirectory -Force | Out-Null
try {
    @{
        private = $true
        scripts = @{
            outer = 'npm run inner --silent'
            inner = 'node probe.cjs'
            npxProbe = 'npx --offline --no-install --call "node probe.cjs"'
            failure = 'npm run fail --silent'
            fail = 'node -e "process.exit(7)"'
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $fixtureDirectory 'package.json') -Encoding utf8NoBOM
    @{node = (Get-MuNode); version = ('v' + $script:MuVersions.node)} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixtureDirectory 'expected.json') -Encoding utf8NoBOM
    @'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const expected = JSON.parse(fs.readFileSync('expected.json', 'utf8'));
const canonical = path => {
  const resolved = fs.realpathSync(path);
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
};
assert.equal(process.version, expected.version);
assert.equal(canonical(process.execPath), canonical(expected.node));
assert.equal(canonical(process.env.npm_node_execpath), canonical(expected.node));
console.log('Nested npm/npx and its child use the pinned Node runtime.');
'@ | Set-Content -LiteralPath (Join-Path $fixtureDirectory 'probe.cjs') -Encoding utf8NoBOM
    Push-Location $fixtureDirectory
    try {
        foreach ($name in @('outer', 'npxProbe')) {
            Invoke-MuNpm -Arguments @('run', $name, '--silent')
            if ($LASTEXITCODE -ne 0) { throw "$name failed with $LASTEXITCODE" }
            if ($env:PATH -cne $originalPath -or $env:PLAYWRIGHT_BROWSERS_PATH -cne $originalBrowserCache) {
                throw 'npm invocation did not restore environment variables'
            }
        }
        Invoke-MuNpm -Arguments @('run', 'failure', '--silent')
        if ($LASTEXITCODE -ne 7) { throw 'Nested npm failure exit code was not preserved' }
        if ($env:PATH -cne $originalPath -or $env:PLAYWRIGHT_BROWSERS_PATH -cne $originalBrowserCache) {
            throw 'Failing npm invocation did not restore environment variables'
        }
        $global:LASTEXITCODE = 0
    } finally { Pop-Location }
    Write-Host 'Toolchain npm runtime, npx, failure propagation and environment restoration passed.'
} finally {
    foreach ($name in @('package.json', 'expected.json', 'probe.cjs')) {
        $fixtureFile = Join-Path $fixtureDirectory $name
        if (Test-Path -LiteralPath $fixtureFile) { Remove-Item -LiteralPath $fixtureFile -Force }
    }
    Remove-Item -LiteralPath $fixtureDirectory -Force
}
