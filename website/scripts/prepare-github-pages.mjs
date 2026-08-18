import { access, rename, rm } from "node:fs/promises";

const exportRoot = new URL("../dist/client/", import.meta.url);
const prefixedAssets = new URL("MuBangumi/_next/", exportRoot);
const publishedAssets = new URL("_next/", exportRoot);

await access(prefixedAssets);
await rm(publishedAssets, { recursive: true, force: true });
await rename(prefixedAssets, publishedAssets);
await rm(new URL("MuBangumi/", exportRoot), { recursive: true, force: true });
