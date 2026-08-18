import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const exportRoot = new URL("../dist/client/", import.meta.url);

test("exports a GitHub Pages-ready homepage", async () => {
  const html = await readFile(new URL("index.html", exportRoot), "utf8");

  assert.match(html, /<title>MuBangumi — 简单又好看的 Bangumi 客户端<\/title>/i);
  assert.match(html, /可交互演示/);
  assert.match(html, /标记下一集/);
  assert.match(html, /参考与致谢/);
  assert.match(html, /https:\/\/wweiyi2004\.github\.io\/MuBangumi\//);
  assert.match(html, /\/MuBangumi\/_next\/static\//);
  assert.doesNotMatch(html, /(?:src|href)="\/_next\//);

  const scriptPath = html.match(/src="(\/MuBangumi\/_next\/static\/[^"]+\.js)"/)?.[1];
  assert.ok(scriptPath, "the exported page should reference a client JavaScript bundle");
  await access(new URL(`.${scriptPath.replace("/MuBangumi", "")}`, exportRoot));
  await assert.rejects(access(new URL("MuBangumi/_next/", exportRoot)));

  await Promise.all([
    access(new URL(".nojekyll", exportRoot)),
    access(new URL("favicon.svg", exportRoot)),
    access(new URL("og.png", exportRoot)),
  ]);
});
