import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const root = new URL("../", import.meta.url);
export const bracesPatch = JSON.parse(
  readFileSync(new URL("security/braces-patch.json", root), "utf8"),
);

// The upstream patch retains version 3.0.3, so verify its origin and installed
// code before treating the version-based advisory as mitigated.
export function verifyBracesPatch() {
  const lock = JSON.parse(readFileSync(new URL("package-lock.json", root), "utf8"));
  const installations = Object.entries(lock.packages).filter(([name]) =>
    name === "node_modules/braces" || name.endsWith("/node_modules/braces"),
  );
  assert.ok(installations.length > 0, "the patched braces dependency must be installed");
  for (const [directory, entry] of installations) {
    assert.equal(entry.resolved, bracesPatch.resolved, `${directory}: unexpected patch origin`);
    assert.equal(entry.integrity, bracesPatch.integrity, `${directory}: unexpected archive integrity`);
    for (const [file, expectedHash] of Object.entries(bracesPatch.files)) {
      const bytes = readFileSync(new URL(`${directory}/${file}`, root));
      const hash = createHash("sha256").update(bytes).digest("hex");
      assert.equal(hash, expectedHash, `${directory}/${file}: installed patch differs`);
    }
  }
  return true;
}

export function unmitigatedHighFindings(report, patchVerified) {
  const findings = report.vulnerabilities;
  function mitigated(name, ancestors = new Set()) {
    const finding = findings[name];
    if (!patchVerified || !finding?.via?.length || ancestors.has(name)) return false;
    const visited = new Set([...ancestors, name]);
    return finding.via.every((cause) => typeof cause === "string"
      ? mitigated(cause, visited)
      : cause.name === "braces" && cause.url === bracesPatch.advisory);
  }
  return Object.entries(findings)
    .filter(([name, finding]) =>
      ["high", "critical"].includes(finding.severity) && !mitigated(name))
    .map(([name]) => name);
}
