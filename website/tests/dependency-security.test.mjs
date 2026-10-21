import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import test from "node:test";
import { bracesPatch, unmitigatedHighFindings, verifyBracesPatch } from "../scripts/dependency-patches.mjs";

const require = createRequire(import.meta.url);
const braces = require("braces");
const depthError = (error) => error instanceof SyntaxError && /nesting depth exceeds/.test(error.message);

test("every installed braces copy matches the reviewed immutable patch", () => {
  assert.equal(verifyBracesPatch(), true);
});

for (const operation of ["parse", "compile", "expand", "stringify", "default"]) {
  test(`braces ${operation} rejects deeply nested input before stack exhaustion`, () => {
    const source = `
      const braces = require(${JSON.stringify(require.resolve("braces"))});
      for (const [open, close] of [["{", "}"], ["(", ")"]]) {
        const pattern = open.repeat(4000) + "x" + close.repeat(4000);
        try {
          ${operation === "default" ? "braces(pattern)" : `braces.${operation}(pattern)`};
          process.exit(2);
        } catch (error) {
          if (error.name !== "SyntaxError" || !/nesting depth exceeds/.test(error.message)) process.exit(3);
        }
      }
    `;
    execFileSync(process.execPath, ["--stack_size=512", "-e", source], { timeout: 3000 });
  });
}

test("braces walkers also guard caller-supplied deep and cyclic ASTs", () => {
  for (const operation of ["compile", "expand", "stringify"]) {
    let ast = { type: "root", nodes: [] };
    for (let depth = 0; depth < 4000; depth++) ast = { type: "root", nodes: [ast] };
    assert.throws(() => braces[operation](ast), depthError);
    const cyclic = { type: "root", nodes: [] };
    cyclic.nodes.push(cyclic);
    assert.throws(() => braces[operation](cyclic), depthError);
  }
});

test("the patch preserves alternatives, ranges, escapes and ordinary ASTs", () => {
  assert.deepEqual(braces.expand("app/{reading,writing}/*.{js,jsx}"), [
    "app/reading/*.js", "app/reading/*.jsx", "app/writing/*.js", "app/writing/*.jsx",
  ]);
  assert.deepEqual(braces.expand("page-{1..3}.js"), ["page-1.js", "page-2.js", "page-3.js"]);
  assert.deepEqual(braces.expand("a\\{b,c\\}"), ["a{b,c}"]);
  assert.equal(braces.compile(braces.parse("a/{b,c}/d")), "a/(b|c)/d");
  const ordinary = "{".repeat(99) + "x" + "}".repeat(99);
  assert.equal(braces.stringify(ordinary), ordinary);
});

test("source-map-js rejects oversized indexed offsets and still maps valid code", () => {
  const { SourceMapConsumer, SourceNode } = require("source-map-js");
  const map = { version: 3, sources: ["source.js"], names: [], mappings: "AAAA", sourcesContent: ["x"] };
  assert.throws(() => new SourceMapConsumer({
    version: 3, sections: [{ offset: { line: 1e12, column: 0 }, map }],
  }), /Section offset line must not exceed/);
  const node = SourceNode.fromStringWithSourceMap("x", new SourceMapConsumer(map));
  assert.equal(node.toString(), "x");
});

test("Miniflare uses patched sharp and can still rasterize SVG", async () => {
  const miniflareRequire = createRequire(require.resolve("miniflare"));
  const sharp = miniflareRequire("sharp");
  assert.equal(sharp.versions.sharp, "0.35.5");
  const [major, minor, patch] = sharp.versions.rsvg.split(".").map(Number);
  assert.ok(major > 2 || (major === 2 && (minor > 63 || (minor === 63 && patch >= 2))));
  const png = await sharp(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><rect width="2" height="2" fill="red"/></svg>'))
    .png().toBuffer();
  const metadata = await sharp(png).metadata();
  assert.equal(metadata.format, "png");
  assert.equal(metadata.width, 2);
  assert.equal(metadata.height, 2);
});

test("audit mitigation requires a verified patch and follows dependency causes", () => {
  const report = { vulnerabilities: {
    braces: { severity: "high", via: [{ name: "braces", url: bracesPatch.advisory }] },
    micromatch: { severity: "high", via: ["braces"] },
  } };
  assert.deepEqual(unmitigatedHighFindings(report, true), []);
  assert.deepEqual(unmitigatedHighFindings(report, false), ["braces", "micromatch"]);
});

test("a new advisory in the same dependency chain still fails the audit", () => {
  const report = { vulnerabilities: {
    braces: { severity: "high", via: [
      { name: "braces", url: bracesPatch.advisory },
      { name: "braces", url: "https://example.invalid/new-advisory" },
    ] },
    micromatch: { severity: "high", via: ["braces"] },
    unrelated: { severity: "critical", via: [{ name: "unrelated", url: "https://example.invalid/critical" }] },
  } };
  assert.deepEqual(unmitigatedHighFindings(report, true), ["braces", "micromatch", "unrelated"]);
});
