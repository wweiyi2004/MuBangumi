import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.route("**/*", (route) => new URL(route.request().url()).hostname === "127.0.0.1" ? route.continue() : route.abort());
  await page.goto("./");
  await page.getByRole("button", { name: "打开追番", exact: true }).click();
});

const demoOf = (page: import("@playwright/test").Page) => page.getByLabel("可点击的 MuBangumi 产品演示");

test("看完下一集 updates progress, the heatmap and survives tab switches", async ({ page }) => {
  const demo = demoOf(page);
  const tile = demo.locator(".continue-tile", { hasText: "葬送的芙莉莲" });
  await expect(tile).toContainText("已记录 24 / 28 集");
  await expect(demo.getByLabel("每日追番")).toContainText("今日 2 格");
  await tile.getByRole("button", { name: /看完下一集/ }).click();
  await expect(tile).toContainText("已记录 25 / 28 集");
  await expect(demo.getByLabel("每日追番")).toContainText("今日 3 格");
  await demo.getByRole("button", { name: "打开收藏", exact: true }).click();
  await expect(demo.getByRole("heading", { name: "我的收藏" })).toBeVisible();
  await expect(demo.locator(".collection-row", { hasText: "葬送的芙莉莲" })).toContainText("看到 25 / 28");
  await demo.getByRole("button", { name: "打开追番", exact: true }).click();
  await expect(tile).toContainText("已记录 25 / 28 集");
});

test("episode picker records and undoes episodes", async ({ page }) => {
  const demo = demoOf(page);
  await demo.getByRole("button", { name: "选择集数：葬送的芙莉莲" }).click();
  await demo.getByRole("button", { name: "看到第 28 集", exact: true }).click();
  await demo.getByRole("button", { name: "关闭选择集数" }).click();
  const tile = demo.locator(".continue-tile", { hasText: "葬送的芙莉莲" });
  await expect(tile).toContainText("已记录 28 / 28 集");
  await expect(tile.getByRole("button", { name: /已看完/ })).toBeDisabled();
  await demo.getByRole("button", { name: "选择集数：葬送的芙莉莲" }).click();
  await demo.getByRole("button", { name: "看到第 28 集", exact: true }).click();
  await demo.getByRole("button", { name: "关闭选择集数" }).click();
  await expect(tile).toContainText("已记录 27 / 28 集");
});

test("collection status menu, discover topics and profile likes are interactive", async ({ page }) => {
  const demo = demoOf(page);
  await demo.getByRole("button", { name: "打开收藏", exact: true }).click();
  await demo.getByRole("button", { name: "按状态筛选" }).click();
  await demo.getByRole("menuitemradio", { name: "想看" }).click();
  await expect(demo.getByText("状态：想看")).toBeVisible();
  await expect(demo.locator(".collection-row", { hasText: "摇曳露营△" })).toBeVisible();
  await demo.getByRole("button", { name: "打开发现", exact: true }).click();
  await demo.getByRole("tab", { name: "超展开" }).click();
  const topic = demo.locator(".topic-list button").first();
  await expect(topic).toHaveAttribute("aria-pressed", "false");
  await topic.click();
  await expect(topic).toHaveAttribute("aria-pressed", "true");
  await demo.getByRole("button", { name: "打开我的", exact: true }).click();
  const like = demo.locator(".timeline-post button").first();
  await expect(like).toHaveAttribute("aria-pressed", "false");
  await like.click();
  await expect(like).toHaveAttribute("aria-pressed", "true");
});

test("private messages open a conversation and send locally", async ({ page }) => {
  const demo = demoOf(page);
  await demo.getByRole("button", { name: "打开消息", exact: true }).click();
  await demo.locator(".list-row", { hasText: "小夏" }).click();
  await demo.getByLabel("输入回复").fill("周六一起看吧");
  await demo.getByRole("button", { name: "发送" }).click();
  await expect(demo.locator(".bubble-row.mine").last()).toContainText("周六一起看吧");
  await demo.getByRole("button", { name: "返回消息列表" }).click();
  await expect(demo.locator(".list-row", { hasText: "小夏" })).toContainText("周六一起看吧");
});

test("homepage fits the viewport and loads without JavaScript exceptions", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.reload();
  await page.getByRole("button", { name: "打开发现", exact: true }).click();
  await expect(demoOf(page).getByRole("heading", { name: "发现", exact: true })).toBeVisible();
  const geometry = await page.evaluate(() => ({
    width: window.innerWidth, scroll: document.documentElement.scrollWidth,
    overflow: [...document.querySelectorAll("body *")].map((element) => ({
      element: `${element.tagName}.${element.className}`, right: element.getBoundingClientRect().right,
    })).filter((item) => item.right > window.innerWidth + 1).slice(0, 8),
  }));
  expect(geometry.scroll, JSON.stringify(geometry)).toBeLessThanOrEqual(geometry.width);
  expect(errors).toEqual([]);
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

test("demo remains under user control with reduced motion and keyboard skip", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  const demo = page.getByLabel("可点击的 MuBangumi 产品演示");
  await demo.getByRole("button", { name: "打开收藏", exact: true }).click();
  await page.clock.install();
  await page.clock.fastForward(16000);
  await expect(demo.getByRole("button", { name: "打开收藏", exact: true })).toHaveAttribute("aria-pressed", "true");
  await page.goto("./");
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "跳到主要内容" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator("#main-content")).toBeFocused();
});

test("theme toggle overrides a dark system setting and is remembered", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.reload();
  const background = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  expect(await background()).toBe("rgb(16, 16, 20)");
  await page.getByRole("button", { name: "切换到浅色主题" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  expect(await background()).toBe("rgb(251, 250, 249)");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  expect(await background()).toBe("rgb(251, 250, 249)");
  await expect(page.getByRole("button", { name: "切换到深色主题" })).toBeVisible();
});
