# MuBangumi 项目主页

这是 MuBangumi 的独立项目主页，使用 React、vinext 和 Cloudflare Workers 构建。它与仓库根目录的 Flutter 应用互不影响，可以单独开发和发布。

首屏包含一个纯前端的可交互产品演示：可以切换首页、收藏、发现和社区，选择番剧并推进观看进度。演示数据只存在于当前页面，不会连接或修改真实的 Bangumi 账号。进度会同步到演示收藏列表；默认不自动切页，轮播须主动开启，并在后台、离开可视区域或系统减少动态效果时暂停。

主页包含 2.4.2 更新介绍、Android / Windows 的明确下载入口和安装升级、数据范围、演示与反馈的常见问题。iOS 明确标为暂无安装包；Gitee 仅作为可能延迟的镜像入口，不代替 GitHub 发行记录。布局和主导航覆盖 320px 窄屏，非官方声明在手机端保留。

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

GitHub Pages 静态版本使用：

```powershell
npm run test:pages
```

静态文件会生成到 `dist/client/`，并由仓库的 GitHub Actions 工作流自动发布。

## 修改位置

- `app/page.tsx`：主页内容、下载与问答区块
- `app/release.ts`：当前正式版与两份已校验的安装包地址；发版后同步版本、构建号、日期与文件名
- `app/ProductDemo.tsx`：首屏产品演示的状态和点击交互
- `app/globals.css`：配色、布局、响应式样式和页面动效
- `app/layout.tsx`：页面标题、描述和社交分享信息
- `public/favicon.svg`：项目图标
- `public/og.png`：社交平台分享封面

主页中的下载和源码按钮分别指向项目的 GitHub Releases 与仓库首页。

页面底部的“参考与致谢”区块记录了项目实际使用的数据来源、技术项目、功能灵感和网页呈现参考；新增来源时应同步维护该区块，并继续保留非官方声明。
