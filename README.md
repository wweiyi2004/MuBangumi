# MuBangumi

MuBangumi 是一个使用 Flutter 编写的第三方 Bangumi 追番客户端，一套代码覆盖 Android、iOS 和 Windows。

> 本项目是非官方客户端，与 Bangumi 番组计划官方无隶属关系。条目、收藏和章节数据来自 [Bangumi API](https://github.com/bangumi/api)。

## 已实现

- 使用 Bangumi OAuth 登录，自动保存并刷新登录凭据
- 保留个人 Access Token 作为备用登录方式
- 同步 Bangumi 全类型收藏（动画 / 书籍 / 音乐 / 游戏 / 三次元）
- 收藏状态文案按类型切换（想看/想读/想听/想玩 等）
- 在首页和收藏卡片直接“点格子”，切换单集的看过、想看、抛弃状态
- 查看在看进度，一键将真实的下一集标记为“看过”
- 查看条目详情、简介、评分、标签和章节列表
- 按条目类型、状态、进度、个人评分和完成度筛选、排序收藏
- 搜索多类型 Bangumi 条目；动画支持季度浏览
- 修改条目收藏状态和单集观看状态
- 好友列表；点击好友/时间线/话题头像进入用户主页，查看追番统计与公开收藏
- 借鉴超合金组件：评分详情与争议度、好友看？、看过自动补进度、楼主/好友高亮
- 本地「新番表」：用 Bangumi 条目信息，自己按周几安排本季追番（本地存储）
- 原生浏览超展开、小组最新话题、所有小组、主题正文与嵌套回复
- 超展开支持按全部、小组、条目、章节和人物分类筛选
- 登录、发帖、回复和加入小组时进入内嵌的 Bangumi 官方页面
- 手机底部导航与 Windows 宽屏侧栏自适应布局

Bangumi 当前公开 OpenAPI 不提供小组、帖子或回复接口。MuBangumi 会解析 Bangumi 的公开 HTML，将超展开、小组列表和话题内容渲染为原生 Flutter 界面，并使用两分钟内存缓存减少重复请求；如果网站结构发生变化，解析规则可能需要随之更新。

写操作仍由 Bangumi 官方网页完成。API 的 OAuth 登录与网站 Cookie 是两套独立会话，因此首次发帖、回复或加入小组时，需要在官网操作页面内再登录一次；登录状态随后由系统 WebView 保留。Windows 端需要 Microsoft Edge WebView2 Runtime（Windows 11 和较新的 Windows 10 通常已预装）。

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

构建时注入内置 OAuth 应用（回调地址必须是 `http://127.0.0.1:43927/oauth/callback`）：

```powershell
flutter run -d windows --dart-define=BGM_CLIENT_ID=你的AppID --dart-define=BGM_CLIENT_SECRET=你的AppSecret
```

配置后登录页显示「使用 Bangumi 一键登录」，无需用户再填 Secret。

> 注意：`client_secret` 会出现在客户端内，有被提取滥用的风险。公开仓库请用 CI 密钥注入，不要把真实 Secret 写进源码。更稳妥的长期方案是自建后端换 Token。

### 自定义 OAuth / 备用

- 登录页「高级：自定义 OAuth」可填写自己的 App ID / Secret。
- 也可展开「Access Token 备用登录」，使用 [Bangumi 个人令牌](https://next.bgm.tv/demo/access-token)。

Token 与 Secret 由 `flutter_secure_storage` 保存在系统安全存储中，到期会自动刷新。

## 构建

Windows：

```powershell
flutter build windows --release
```

Android APK：

```powershell
flutter build apk --release
```

Android App Bundle：

```powershell
flutter build appbundle --release
```

构建产物分别位于 `build/windows/x64/runner/Release/` 和 `build/app/outputs/`。

## 项目结构

```text
lib/
├─ core/
│  ├─ auth/          # OAuth 授权、回调与 Token 刷新
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

所有请求统一携带明确的 `User-Agent`；需要登录的请求使用 `Authorization: Bearer ...` 请求头。
