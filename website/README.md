# MuBangumi 项目主页

这是 MuBangumi 的独立项目主页，使用 React、vinext 和 Cloudflare Workers 构建。它与仓库根目录的 Flutter 应用互不影响，可以单独开发和发布。

首屏包含一个纯前端的可交互产品演示：可以切换首页、收藏、发现和社区，选择番剧并推进观看进度。演示数据只存在于当前页面，不会连接或修改真实的 Bangumi 账号。

## 本地运行

使用 `.node-version` 指定的 Node.js 22.23.2，与 CI 一致。主工程不再安装未使用的 Drizzle/D1 示例依赖；原模板保留在 `docs/archive/WEBSITE_D1_SCAFFOLD.md`。

```powershell
cd website
npm ci
npm run dev
```

浏览器打开 `http://localhost:3000`。

## 验证构建

```powershell
npm run check
npm run audit:security
npx playwright install chromium
npm run test:browser
```

`check` 依次运行 lint、类型检查、Workers 环境下的 SSR 检查和静态导出测试。浏览器测试在桌面和手机视口验证进度、筛选、贴贴、话题预览和横向溢出；只访问本地静态文件。

## 依赖安全修复

`overrides` 将 `sharp` 固定到 0.35.5、`source-map-js` 固定到 1.2.2，分别修复 [librsvg 漏洞](https://github.com/advisories/GHSA-wq5f-xc86-pv6w)和[索引 source map 拒绝服务漏洞](https://github.com/advisories/GHSA-68fv-2mgg-jv7q)。

`braces` 的[递归栈溢出漏洞](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm)尚无正式修复版。当前临时采用上游待合并的 [PR #78](https://github.com/micromatch/braces/pull/78)，固定提交 `97308a01d091b211cf015314a2d0696da28a5392` 的 HTTPS 源码包与完整性校验值；它限制字符串解析及调用方提供 AST 的递归深度。此补丁保留原来的 `3.0.3` 版本号，原始 npm 审计仍会列出该告警及其依赖链。

`audit:security` 先验证安装代码的 SHA-256、锁文件来源和完整性，再运行深层嵌套字符串/AST、普通 glob、source map 与 SVG 转换回归。审计日志保留完整的原始 npm 报告；仅该漏洞及完全由它导致的告警可标记为已缓解。补丁不匹配、同一依赖的新漏洞及其他 high/critical 告警都会失败。`security/braces-patch.json` 记录了补丁来源与校验值。

上游发布正式修复版后，应改用正式 npm 包，并一并移除这个临时补丁清单和专用审计判断，保留攻击回归。补丁没有覆盖库的所有资源耗尽风险，不能据此认定任意 glob 或 AST 输入均安全。

GitHub Pages 静态版本使用：

```powershell
npm run test:pages
```

静态文件会生成到 `dist/client/`，并由仓库的 GitHub Actions 工作流自动发布。

## 修改位置

- `app/page.tsx`：主页内容和区块结构
- `app/ProductDemo.tsx`：首屏产品演示的状态和点击交互
- `app/globals.css`：配色、布局、响应式样式和页面动效
- `app/layout.tsx`：页面标题、描述和社交分享信息
- `public/favicon.svg`：项目图标
- `public/og.png`：社交平台分享封面

主页中的下载和源码按钮分别指向项目的 GitHub Releases 与仓库首页。

页面底部的“参考与致谢”区块记录了项目实际使用的数据来源、技术项目、功能灵感和网页呈现参考；新增来源时应同步维护该区块，并继续保留非官方声明。
