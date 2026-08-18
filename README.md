# MuBangumi

项目主页：<https://wweiyi2004.github.io/MuBangumi/>

MuBangumi 是一个使用 Flutter 编写的第三方 Bangumi 追番客户端，一套代码覆盖 Android、iOS 和 Windows。

> 本项目是非官方客户端，与 Bangumi 番组计划官方无隶属关系。条目、收藏和章节数据来自 [Bangumi API](https://github.com/bangumi/api)。

当前版本：**v2.0.0**

## 原生 Android 版本

仓库的 `native-android/` 包含独立的 Kotlin + Jetpack Compose 原生实现，不依赖 Flutter 运行时。构建方法、已迁移功能和工程结构见 [`native-android/README.md`](native-android/README.md)。

## 已实现

- 使用 Bangumi OAuth 登录，自动保存并刷新登录凭据
- 保留个人 Access Token 作为备用登录方式
- 同步 Bangumi 全类型收藏（动画 / 书籍 / 音乐 / 游戏 / 三次元）
- 收藏状态文案按类型切换（想看/想读/想听/想玩 等）
- 在首页和收藏卡片直接“点格子”，切换单集的看过、想看、抛弃状态
- 查看在看进度，一键将真实的下一集标记为“看过”
- 「番会荐」：按个人收藏口味或一句话需求，从 Bangumi 筛选推荐动画
- 查看条目详情、简介、评分、平台 / 官网 / NSFW、标签、章节、角色 / 制作人员 / 关联条目
- 条目历史评分 / 排名 / 收藏变化曲线（数据来自 [netaba.re](https://netaba.re)）
- 发现页「评分趋势」：近月涨跌榜、完结波动与口碑提升排行
- 用户主页展示最近动态（时光机）
- 角色页与人物页（出演作品、声优 / 饰演角色互相跳转）
- 公司事实档案：按年份、职位和参与集数浏览关联作品，明确标记待补全或未收录的数据
- 条目角色横向卡片、制作人员职位分组和关联作品海报轨道，减少超长名单
- 条目吐槽分页、讨论列表；标签一点即可跳转发现搜索
- 收藏完整编辑：状态、评分、短评、标签、隐私；书籍可改卷/话进度
- 按条目类型、状态、进度、个人评分和完成度筛选、排序收藏
- 搜索条目 / 角色 / 人物；动画支持季度浏览与无限滚动
- 官方「每日放送」日历（与本地新番表独立）
- 修改条目收藏状态和单集观看状态（含 SP/OP/ED 筛选；进度以本篇为准）
- 好友列表；原生加/删好友（P1）；本客户端二维码出示 / 扫描加好友
- 点击好友/时间线/话题头像进入用户主页
- 用户收藏口味对比：综合收藏重合、共同评分相关性与评分差，并显示样本置信度
- 用户主页查看共同好友
- 网络线路测速；反代 GET 遇到瞬时超时或网关错误会自动重试一次
- 发现页可手动输入浏览年份，季度浏览支持下一年
- 条目、RSS 和更新说明中的链接只打开 http(s)；社区内嵌页只嵌入 Bangumi 域名
- 收藏统计与年度回顾：类型 / 状态 / 评分 / 标签分布，支持完整 JSON 导出
- 用户本地备注与内容屏蔽（SQLite，仅保存在本机；时间线和话题内容可临时展开）
- 原生电波提醒列表（P1，支持标已读、应用内打开话题 / 时光机）；「我的」Tab 未读角标
- 站内短信：原生收件箱 / 会话 / 发送（网站 Cookie；失败可回退网页）
- Shorebird 热更新检查与重启提示（需 shorebird release 包）
- 自动检测 GitHub Release 整包更新，Markdown 公告弹窗可前往下载或跳过此版本
- 收藏本地快照与发现页 stale-while-revalidate
- 同步网站登录（Cookie 安全存储，供私信等网页能力）
- 深色 / 浅色 / 跟随系统主题
- 自定义背景图 + 分层毛玻璃（壁纸 / 压暗 / 磨砂强度 / 玻璃不透明度）
- 借鉴超合金组件：评分详情与争议度、好友看？、看过自动补进度、楼主/好友高亮
- 本地「新番表」：用 Bangumi 条目信息，自己按周几安排本季追番（本地存储）
- 新番表导出为 PNG 海报（浅色 / 深色），桌面保存到下载目录并可打开位置
- 原生浏览超展开、小组最新话题、所有小组、主题正文与嵌套回复
- 超展开支持按全部、小组、条目、章节和人物分类筛选
- 社区发帖 / 回复等写操作走 next.bgm.tv P1 + 官方 Turnstile 验证页；加组等仍可走内嵌官网
- 社区编辑器提供 BBCode 工具栏；长内容自动折叠，超过 180 天未更新的话题回复前提示
- 手机底部导航与 Windows 宽屏侧栏自适应布局
- 内容优先的海报化首页与发现页；首页提供新番表、每日放送、番会荐和找新番快捷入口
- 全应用窄屏适配：页边距 / 标题字号 / 列表密度 / 导航栏标签 / 新番表格子防溢出
- 性能优化：发现结果与长话题懒构建、超长章节分批显示、按屏幕尺寸解码壁纸并减少重复模糊

Bangumi 当前公开 OpenAPI 不提供完整的小组、私信与通知接口。MuBangumi 对社区列表与话题使用 P1 JSON（失败时回退 HTML 解析），并使用短时缓存减少重复请求；如果网站结构发生变化，解析规则可能需要随之更新。

API 的 OAuth 登录可直接调用 next.bgm.tv P1 完成电波提醒与加/删好友。站内短信已改为**原生界面**（收件箱 / 会话 / 发送），通过「我的 → 同步网站登录」保存的官网 Cookie 访问 `bgm.tv/pm` HTML 接口；失败时可回退网页版。小组加入/退出等仍可用内嵌 WebView。退出 OAuth 时会一并清除网站会话。Windows 端需要 Microsoft Edge WebView2 Runtime（Windows 11 和较新的 Windows 10 通常已预装）。

## 开始运行

环境要求：Flutter 3.44 或兼容版本、Dart 3.12 或兼容版本。

```powershell
flutter pub get
flutter run -d windows
```

连接 Android 设备后：

```powershell
flutter run -d android
```

iOS 工程已生成，但 iOS 编译和签名必须在安装了 Xcode 的 macOS 上完成。

## 登录

### 一键登录（推荐发布方式）

构建时注入内置 OAuth 应用（回调地址必须是 `http://127.0.0.1:43927/oauth/callback`）。
先复制本地配置模板并填写真实凭据：

```powershell
Copy-Item config/oauth.local.json.example config/oauth.local.json
# 编辑 config/oauth.local.json 后运行：
flutter run -d windows --dart-define-from-file=config/oauth.local.json
```

`config/oauth.local.json` 已被 Git 忽略。配置后登录页显示「使用 Bangumi 一键登录」，
无需用户再填写 Secret；发布构建也不会把 Secret 写进命令历史。

> 注意：`client_secret` 会出现在客户端内，有被提取滥用的风险。公开仓库请用 CI 密钥注入，不要把真实 Secret 写进源码。更稳妥的长期方案是自建后端换 Token。

### 自定义 OAuth / 备用

- 登录页「其他登录方式与设置」可填写自己的 App ID / Secret。
- 同一面板也提供 Access Token 备用登录，可使用 [Bangumi 个人令牌](https://next.bgm.tv/demo/access-token)。

Token 与 Secret 由 `flutter_secure_storage` 保存在系统安全存储中，到期会自动刷新。

## 热更新（Shorebird）

应用使用 [Shorebird](https://shorebird.dev) 做 **Dart 代码热更新**（Android / Windows 等）。

- 登录后进入主界面会延迟检查：有 Shorebird patch 时下载并弹窗展示 **Markdown 更新说明**（含 GitHub Release body），可「退出并生效 / 稍后」。
- 若没有可应用的热更新，但 GitHub 上有更新的正式版，会再弹 **Markdown 公告**，可「前往下载 / 稍后 / 跳过此版本」。跳过只作用于该 tag，下一个版本仍会提示。
- 「我的」→「检查更新」可手动检查；手动检查仍会展示已跳过的版本。
- 必须用 Shorebird 打的包用户才能收到 patch；普通 `flutter run` / `flutter build` **不会**启用 updater。
- 改原生代码、资源或 Flutter 引擎版本时，需要重新 `shorebird release`，不能只 patch。

```powershell
# 安装 CLI 后登录：shorebird login
# 初始化（本仓库已有 shorebird.yaml）

# 发整包基线（分发给用户的安装包）
.\tool\build_release.ps1 -Target windows -Shorebird
.\tool\build_release.ps1 -Target appbundle -Shorebird

# 只改了 Dart → 推送热更新
shorebird patch windows '--' --dart-define-from-file=config/oauth.local.json
shorebird patch android '--' --dart-define-from-file=config/oauth.local.json
```

`shorebird.yaml` 中 `auto_update: false`，由应用内控制检查与下载，以便展示重启弹窗。

## 构建

Windows：

```powershell
# 推荐用 Shorebird，便于后续 patch
.\tool\build_release.ps1 -Target windows -Shorebird

# 或普通 Flutter 构建（无热更新）
.\tool\build_release.ps1 -Target windows
```

Android APK：

```powershell
.\tool\build_release.ps1 -Target apk -Shorebird
# 或
.\tool\build_release.ps1 -Target apk
```

Android App Bundle：

```powershell
.\tool\build_release.ps1 -Target appbundle -Shorebird
# 或
.\tool\build_release.ps1 -Target appbundle
```

Android 正式构建需要独立上传密钥，不能使用调试签名。先复制
`android/key.properties.example` 为 `android/key.properties`，填写密钥路径、别名和密码；
密钥文件与 `key.properties` 已被 Git 忽略。配置缺失时 Release 构建会直接失败，避免误发调试签名包。

构建产物分别位于 `build/windows/x64/runner/Release/` 和 `build/app/outputs/`。

## 项目结构

```text
lib/
├─ core/
│  ├─ auth/          # OAuth 授权、回调与 Token 刷新
│  ├─ insights/      # 收藏对比、评分相似度与个人统计
│  ├─ network/       # Bangumi API、分页、错误处理
│  ├─ storage/       # OAuth 配置与登录凭据安全存储
│  └─ theme/         # Material 3 主题
├─ models/           # 用户、条目、收藏、章节模型
├─ screens/          # 登录、首页、收藏、发现、社区、详情、我的
├─ state/            # 会话、收藏同步、追番进度状态
└─ widgets/          # 封面、条目卡片、空状态等复用组件
```

主要使用的 API：

- `GET /v0/me`
- `GET /v0/users/{username}/collections`（支持全类型或按 `subject_type`）
- `GET next.bgm.tv/p1/users/{username}/friends`
- `GET /v0/subjects/{subject_id}`
- `POST /v0/search/subjects`
- `GET /v0/episodes`
- `GET /v0/users/-/collections/{subject_id}/episodes`
- `POST /v0/users/-/collections/{subject_id}`
- `PUT /v0/users/-/collections/-/episodes/{episode_id}`
- netaba.re：`GET https://api.netaba.re/subject/{id}`、`/trending`、`/score-increases`

所有请求统一携带明确的 `User-Agent`；需要登录的请求使用 `Authorization: Bearer ...` 请求头。评分历史为第三方公开数据，与 Bangumi 官方无隶属关系。
