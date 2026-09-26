import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";
import { unstable_dev } from "wrangler";

const templateRoot = new URL("../", import.meta.url);

async function render() {
  // The production bundle imports cloudflare:workers; exercise the same
  // runtime instead of relying on accidental compatibility with Node's loader.
  const worker = await unstable_dev("dist/server/index.js", {
    config: "dist/server/wrangler.json", ip: "127.0.0.1", port: 0,
    local: true, persist: false, envFiles: [], logLevel: "error",
    experimental: { disableExperimentalWarning: true, disableDevRegistry: true,
      watch: false, showInteractiveDevSession: false, enableContainers: false },
  });
  try {
    const response = await worker.fetch("/", { headers: { accept: "text/html" } });
    return new Response(await response.text(), { status: response.status, headers: response.headers });
  } finally {
    await worker.stop();
  }
}

test("server-renders the MuBangumi homepage", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>MuBangumi — 简单又好看的 Bangumi 客户端<\/title>/i);
  assert.match(html, /追番这件事/);
  assert.match(html, /可交互演示/);
  assert.match(html, /标记下一集/);
  assert.match(html, /从“想看”到“看完”/);
  assert.match(html, /参考与致谢/);
  assert.match(html, /https:\/\/zcode\.z\.ai\/en/);
  assert.match(html, /https:\/\/bangumi\.tv\/dev\/garage/);
  assert.match(html, /不代表任何官方合作、隶属关系或背书/);
  assert.match(html, /https:\/\/github\.com\/wweiyi2004\/MuBangumi\/releases/);
  assert.match(html, /property="og:image"/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/);
});

test("removes all disposable starter content", async () => {
  const [page, demo, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/ProductDemo.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /MuBangumi/);
  assert.match(demo, /^"use client";/);
  assert.match(demo, /markNextEpisode/);
  assert.match(demo, /aria-pressed/);
  assert.match(demo, /setActiveTab/);
  assert.match(layout, /export const metadata/);
  assert.match(layout, /force-static/);
  assert.doesNotMatch(layout, /next\/headers/);
  assert.match(layout, /openGraph/);
  assert.match(packageJson, /"name": "mubangumi-homepage"/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  await assert.rejects(
    access(new URL("app/_sites-preview/SkeletonPreview.tsx", templateRoot)),
  );
});
