# 条目、图标、通知、历史对比与字体

- 制作人员移至独立页面，按职位列出，支持姓名/职位搜索和人物详情导航；条目页只保留入口。
- 应用自身的图标通过 `AnimeIcon` 绘制 SVG。常用语义采用猫耳、星光和丝带线稿；方向、警告、状态等保留功能辨识度。矢量资源来自原创图案及现有 Material/Cupertino 字形，许可随资源保存。
- 好友申请的状态检查逐项结束，单个网络查询最多等待 6 秒；短期状态持久化按账号隔离。主动刷新重新查询，迟到的旧账号状态和接受响应不更新新账号界面。
- 评分趋势页新增「历史对比」。支持从收藏或公开搜索选择最多 6 部作品，共用日期轴/评分轴；30/90/365 天及全时间窗口；点击或悬停读取最近的实际样本。未收录、单样本、网络失败逐作品说明，不伪造折线。
- 原「我的收藏」是榜单过滤，不等同于所有收藏的历史。界面说明这一点，历史对比可直接请求未上榜条目。
- 验证桥接只接收 `next.bgm.tv/p1/turnstile` 官方 `turnstile-container` 与应用完成回调的令牌。入口 clearance 页面及子框架的响应不再作为发帖令牌；不覆盖 Turnstile 的 render 和浏览器导航方法。
- 「设置 → 外观 → 字体」保留默认字体；霞鹜文楷及 Noto Sans SC 仅在点击下载时获取。支持进度、取消、离线恢复、移除和回到默认。下载有固定版本、长度及哈希校验，校验在独立 isolate 完成；字体文件不进入安装资源。

## 验证边界

针对性测试覆盖独立制作人员列表、逐项查询/超时、持久缓存账号归属、旧响应拒绝、历史请求移除后重选、账号切换时选择器收起旧收藏、图标语义和尺寸、字体无自动下载/取消/损坏校验，以及小屏大字号。桥接 JS 使用 Node 合成页面执行，覆盖官方组件、clearance 页面和子框架。

未使用真实账号发送小组讨论或日志。上述令牌来源问题有可复现的合成回归，不将其等同于用户当前网络环境下的全部 CAPTCHA 问题。真实发帖、系统字体加载和移动设备验收仍需实际操作。

## 上游依据

- [Bangumi 官方验证页模板](https://github.com/bangumi/server-private/blob/master/templates/turnstile.liquid)
- [Bangumi 验证服务与一次性令牌校验](https://github.com/bangumi/server-private/blob/master/lib/services/turnstile.ts)
- [Cloudflare WebView 集成要求](https://developers.cloudflare.com/turnstile/get-started/mobile-implementation/)
- [霞鹜文楷 v1.522](https://github.com/lxgw/LxgwWenKai/releases/tag/v1.522)
- [固定版本 Noto Sans SC](https://github.com/google/fonts/tree/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notosanssc)
