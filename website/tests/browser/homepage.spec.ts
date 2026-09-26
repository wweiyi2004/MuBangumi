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
