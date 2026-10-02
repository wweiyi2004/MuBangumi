import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.route("**/*", (route) => new URL(route.request().url()).hostname === "127.0.0.1" ? route.continue() : route.abort());
  await page.goto("./");
  await page.getByRole("button", { name: "打开首页", exact: true }).click();
});

test("episode progress changes and remains after switching tabs", async ({ page }) => {
  const demo = page.getByLabel("可点击的 MuBangumi 产品演示");
  const progress = demo.locator(".progress-copy p");
  const before = await progress.innerText();
  const episode = Number(before.match(/第 (\d+) 话/)?.[1]);
  await demo.getByRole("button", { name: /标记下一集/ }).click();
  await expect(progress).toContainText(`第 ${episode + 1} 话`);
  await demo.getByRole("button", { name: "打开收藏", exact: true }).click();
  await expect(demo.getByRole("heading", { name: "我的收藏" })).toBeVisible();
  await demo.getByRole("button", { name: "打开首页", exact: true }).click();
  await expect(progress).toContainText(`第 ${episode + 1} 话`);
});

test("collection filters and community reactions are interactive", async ({ page }) => {
  const demo = page.getByLabel("可点击的 MuBangumi 产品演示");
  await demo.getByRole("button", { name: "打开收藏", exact: true }).click();
  await demo.getByRole("button", { name: "想看", exact: true }).click();
  await expect(demo.getByRole("button", { name: "想看", exact: true })).toHaveAttribute("aria-pressed", "true");
  await demo.getByRole("button", { name: "打开社区", exact: true }).click();
  const like = demo.locator(".timeline-post button").first();
  await expect(like).toHaveAttribute("aria-pressed", "false");
  await like.click();
  await expect(like).toHaveAttribute("aria-pressed", "true");
  await demo.getByRole("button", { name: "热门话题", exact: true }).click();
  await demo.locator(".topic-list button").first().click();
  await expect(demo.getByText("已打开话题预览")).toBeVisible();
});

test("homepage fits the viewport and loads without JavaScript exceptions", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.reload();
  await page.getByRole("button", { name: "打开发现", exact: true }).click();
  await expect(page.getByLabel("可点击的 MuBangumi 产品演示").getByRole("heading", { name: "发现", exact: true })).toBeVisible();
  const geometry = await page.evaluate(() => ({
    width: window.innerWidth, scroll: document.documentElement.scrollWidth,
    overflow: [...document.querySelectorAll("body *")].map((element) => ({
      element: `${element.tagName}.${element.className}`, right: element.getBoundingClientRect().right,
    })).filter((item) => item.right > window.innerWidth + 1).slice(0, 8),
  }));
  expect(geometry.scroll, JSON.stringify(geometry)).toBeLessThanOrEqual(geometry.width);
  expect(errors).toEqual([]);
});

test("episode grid sets progress and the collection follows it", async ({ page }) => {
  const demo = page.getByLabel("可点击的 MuBangumi 产品演示");
  await demo.getByRole("button", { name: "看到第 28 话", exact: true }).click();
  await expect(demo.locator(".progress-copy p")).toContainText("第 28 话");
  await expect(demo.getByRole("button", { name: /本季已看完/ })).toBeDisabled();
  await demo.getByRole("button", { name: "打开收藏", exact: true }).click();
  await demo.getByRole("button", { name: /^看过/ }).click();
  await expect(demo.locator(".collection-row", { hasText: "葬送的芙莉莲" })).toContainText("28 / 28");
});

test("downloads link the current packages and explain unavailable iOS", async ({ page }) => {
  const downloads = page.locator("#platforms");
  await expect(downloads).toContainText("2.4.2");
  await expect(downloads.getByRole("link", { name: "下载 Android" })).toHaveAttribute("href", /v2\.4\.2%2B4032\/MuBangumi-2\.4\.2-build4032-android\.apk$/);
  await expect(downloads.getByRole("link", { name: "下载 Windows" })).toHaveAttribute("href", /v2\.4\.2%2B4032\/MuBangumi-2\.4\.2-build4032-windows-x64\.zip$/);
  await expect(downloads.getByText("本版未提供安装包", { exact: true })).toBeVisible();
  await expect(downloads.getByRole("link", { name: /iOS/ })).toHaveCount(0);
});

test("help answers open from the keyboard", async ({ page }) => {
  const first = page.locator("#faq details").first();
  await first.locator("summary").focus();
  await page.keyboard.press("Enter");
  await expect(first).toHaveAttribute("open", "");
  await expect(first).toContainText("新的空目录");
});

test("320px with enlarged text keeps navigation, downloads and disclaimer", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await page.addStyleTag({ content: "html { font-size: 20px; }" });
  await expect(page.getByRole("navigation", { name: "主导航" }).getByRole("link", { name: "下载", exact: true })).toBeVisible();
  await expect(page.locator("#platforms").getByRole("link", { name: "下载 Android" })).toBeVisible();
  await expect(page.locator("footer").getByText("非官方客户端，与 Bangumi 番组计划官方无隶属关系。")).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
});
