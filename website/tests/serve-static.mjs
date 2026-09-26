import { createServer } from "node:http";
import { readFile, access } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { extname, resolve, sep } from "node:path";

const root = fileURLToPath(new URL("../dist/client/", import.meta.url));
await access(resolve(root, "index.html")); // Run build:pages before browser tests.
const mime = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json" };
createServer(async (request, response) => {
  try {
    const url = new URL(request.url, "http://127.0.0.1:41739");
    if (!url.pathname.startsWith("/MuBangumi/")) { response.writeHead(404).end(); return; }
    const relative = decodeURIComponent(url.pathname.slice("/MuBangumi/".length));
    const path = resolve(root, relative || "index.html");
    if (!path.startsWith(resolve(root) + sep)) { response.writeHead(403).end(); return; }
    const bytes = await readFile(path);
    response.writeHead(200, { "Content-Type": mime[extname(path)] ?? "application/octet-stream", "Cache-Control": "no-store" }).end(bytes);
  } catch { response.writeHead(404).end(); }
}).listen(41739, "127.0.0.1");
