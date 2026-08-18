# MuBangumi 项目主页

这是 MuBangumi 的独立项目主页，使用 React、vinext 和 Cloudflare Workers 构建。它与仓库根目录的 Flutter 应用互不影响，可以单独开发和发布。

首屏包含一个纯前端的可交互产品演示：可以切换首页、收藏、发现和社区，选择番剧并推进观看进度。演示数据只存在于当前页面，不会连接或修改真实的 Bangumi 账号。

## 本地运行

需要 Node.js 22.13 或更高版本。

```powershell
cd website
npm ci
npm run dev
```

浏览器打开 `http://localhost:3000`。

## 验证构建

```powershell
npm run lint
npm test
```

`npm test` 会重新构建主页，并检查服务端输出的标题、介绍和关键链接。

## 修改位置

- `app/page.tsx`：主页内容和区块结构
- `app/ProductDemo.tsx`：首屏产品演示的状态和点击交互
- `app/globals.css`：配色、布局、响应式样式和页面动效
- `app/layout.tsx`：页面标题、描述和社交分享信息
- `public/favicon.svg`：项目图标
- `public/og.png`：社交平台分享封面

主页中的下载和源码按钮分别指向项目的 GitHub Releases 与仓库首页。

页面底部的“参考与致谢”区块记录了项目实际使用的数据来源、技术项目、功能灵感和网页呈现参考；新增来源时应同步维护该区块，并继续保留非官方声明。
