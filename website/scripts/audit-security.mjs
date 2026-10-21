import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { bracesPatch, unmitigatedHighFindings, verifyBracesPatch } from "./dependency-patches.mjs";

const verified = verifyBracesPatch();
assert.ok(process.env.npm_execpath, "Run this check with npm run audit:security");
const result = spawnSync(process.execPath, [
  process.env.npm_execpath, "audit", "--json", "--registry=https://registry.npmjs.org",
], { encoding: "utf8", timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
if (result.error) throw result.error;
const report = JSON.parse(result.stdout);
assert.ok(
  [0, 1].includes(result.status) && !report.error && report.auditReportVersion === 2 && report.vulnerabilities,
  `npm audit did not return a valid report: ${result.stderr || result.stdout}`,
);

// Preserve the unfiltered report in CI/verify_all logs. Only the exact patched
// advisory and findings derived exclusively from it can pass this gate.
console.log(JSON.stringify(report, null, 2));
const blocked = unmitigatedHighFindings(report, verified);
const high = Object.entries(report.vulnerabilities)
  .filter(([, finding]) => ["high", "critical"].includes(finding.severity))
  .map(([name]) => name);
const mitigated = high.filter((name) => !blocked.includes(name));
console.log(`Raw npm audit: ${report.metadata.vulnerabilities.high} high, ${report.metadata.vulnerabilities.critical} critical.`);
if (mitigated.length) {
  console.log(`Verified braces patch ${bracesPatch.commit}: ${mitigated.join(", ")}.`);
  console.log(`Upstream patch is pending release: ${bracesPatch.upstreamPullRequest}`);
}
console.log(`Unmitigated high/critical findings: ${blocked.length}.`);
if (blocked.length) {
  console.error(`Security audit failed: ${blocked.join(", ")}`);
  process.exitCode = 1;
}
