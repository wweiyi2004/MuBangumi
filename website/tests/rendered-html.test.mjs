import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const templateRoot = new URL("../", import.meta.url);

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the MuBangumi homepage", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>MuBangumi — 简单又好看的 Bangumi 客户端<\/title>/i);
  assert.match(html, /追番这件事/);
  assert.match(html, /从“想看”到“看完”/);
  assert.match(html, /https:\/\/github\.com\/wweiyi2004\/MuBangumi\/releases/);
  assert.match(html, /property="og:image"/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/);
});

test("removes all disposable starter content", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /MuBangumi/);
  assert.match(layout, /generateMetadata/);
  assert.match(layout, /openGraph/);
  assert.match(packageJson, /"name": "mubangumi-homepage"/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  await assert.rejects(
    access(new URL("app/_sites-preview/SkeletonPreview.tsx", templateRoot)),
  );
});
