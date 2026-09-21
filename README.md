# MuBangumi

项目主页：<https://wweiyi2004.github.io/MuBangumi/>

发布维护：[Gitee 双平台发布与断点续传配置](docs/GITEE_MIRROR.md)。镜像不可用时自动回退 GitHub。

MuBangumi 是一个使用 Flutter 编写的第三方 Bangumi 追番客户端，一套代码覆盖 Android、iOS 和 Windows。

> 本项目是非官方客户端，与 Bangumi 番组计划官方无隶属关系。条目、收藏和章节数据来自 [Bangumi API](https://github.com/bangumi/api)。

当前版本：**v2.3.0+28**

后续体验改进的阶段、验收标准与进展见 [长期体验改进计划](docs/UX_ROADMAP.md)。

## 原生 Android 版本

仓库的 `native-android/` 包含独立的 Kotlin + Jetpack Compose 原生实现，不依赖 Flutter 运行时。构建方法、已迁移功能和工程结构见 [`native-android/README.md`](native-android/README.md)。注意：该模块为**已冻结的原型**，停留在 1.7.0 时代，不随主线维护。

## 已实现

- 实验性「番剧鉴赏 / 番键会」：局域网服务、独立管理页面、MuBangumi 原生 / 网页扫码参与，有名入场、匿名评分评论、实时统计、历史导出与远程服务器连接。入口及验证边界见 [番键会试用说明](docs/qa/banjian-implementation/README.md)；当前不含音频。

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
- 人物 / 角色详情页支持原生收藏与取消收藏，读取当前账号的收藏状态；切换账号后重新加载
- 时光机中的条目、人物、角色和日志可点击进入原生详情，批量收藏支持展开全部；吐槽支持贴贴，自己的动态支持确认后删除（同时删除该动态的回复）
- 「我的 → 我的日志」和用户主页「日志」提供原生分页列表、正文与评论入口；支持发布和编辑自己的日志，正文、标签及可见性一起保存在账号隔离的本机草稿中
- 公司事实档案：按年份、职位和参与集数浏览关联作品，明确标记待补全或未收录的数据
- 条目角色横向卡片、制作人员职位分组和关联作品海报轨道，减少超长名单
- 条目吐槽分页、讨论列表；标签一点即可跳转发现搜索
- 收藏完整编辑：状态、评分、短评、标签、隐私；书籍可改卷/话进度
- 按条目类型、状态、进度、个人评分和完成度筛选、排序收藏
- 搜索条目 / 角色 / 人物；动画支持季度浏览与无限滚动
- 官方「每日放送」日历（与本地新番表独立）
- 修改条目收藏状态和单集观看状态（含 SP/OP/ED 筛选；进度以本篇为准）
- 好友列表；原生加/删好友（P1）；统一扫一扫识别好友与小组二维码；小组二维码可保存、分享或复制官网链接，扫码先打开详情，再由用户选择加入
- 点击好友/时间线/话题头像进入用户主页
- 用户收藏口味对比：综合收藏重合、共同评分相关性与评分差，并显示样本置信度
- 用户主页查看共同好友
- 网络线路测速；反代 GET 遇到瞬时超时或网关错误会自动重试一次
- 短评按账号与作品自动保存本机草稿，离开编辑器或重启后恢复，提交成功后清除；原短评变化时先让用户选择，避免覆盖较新的内容
- 收藏与章节修改离线优先：本地立即落盘并更新界面，联网、回到前台或手动同步后自动补传
- 已读取的章节状态保留本地快照，断网时仍可点格子；连续修改自动合并为最后一次状态
- 收藏与个人章节快照不再因超过 30 天而失效，在缓存容量内优先保留；离线提示显示本地快照时间
- 断网或收藏读取已退回本地数据时，“下一集”直接使用已缓存章节；网络恢复后合并重复事件，补传修改并刷新收藏
- 发现页可手动输入浏览年份，季度浏览支持下一年
- 条目、RSS 和更新说明中的链接只打开 http(s)；社区内嵌页只嵌入 Bangumi 域名
- 收藏统计与年度回顾：类型 / 状态 / 评分 / 标签分布，完整 JSON 可通过系统分享或另存到自选位置
- 用户本地备注与内容屏蔽（SQLite，仅保存在本机；时间线和话题内容可临时展开）
- 原生电波提醒列表（P1，支持标已读、应用内打开话题 / 时光机）；「我的」Tab 未读角标
- 站内短信：原生收件箱 / 会话 / 发送（网站 Cookie；失败可回退网页）；收发件箱支持分页、失败重试，发送后自动刷新
- Shorebird 热更新检查与页内就绪提示，下次启动生效（需 shorebird release 包）
- GitHub 整包更新提供页内提醒、版本对比、更新摘要、明天提醒和跳过；按设备架构下载，展示进度，支持取消、重试及 SHA256 校验
- 收藏本地快照与发现页 stale-while-revalidate
- 统一“Bangumi 账号”入口；应用内 OAuth 登录后核对网站会话是否属于同一用户，私信、小组共用已核验会话；网站失效不清除正常的 API 登录
- 深色 / 浅色 / 跟随系统主题
- 自定义背景图 + 分层毛玻璃（壁纸 / 压暗 / 磨砂强度 / 玻璃不透明度）
- 借鉴超合金组件：评分详情与争议度、好友看？、看过自动补进度、楼主/好友高亮
- 本地「新番表」：用 Bangumi 条目信息，自己按周几安排本季追番（本地存储）
- 新番表季度旁提供“选番”快捷入口，浏览该季度三个月的新番并多选加入；支持分页、去重、按放送日安排或全部待安排，不修改官网收藏
- 新番表中每部番可独立开启每周系统更新提醒并自选时间（Android / iOS / Windows）
- 新番表导出为 PNG 海报（浅色 / 深色），桌面保存到下载目录并可打开位置
- 原生浏览超展开、小组最新话题、所有小组、主题正文与嵌套回复
- 超展开支持条目热门 / 最新、小组全部 / 参加的 / 发表的 / 回复的，以及综合 / 章节 / 角色 / 人物；后四类显示最近最多 200 个讨论，更多历史内容可转到官网
- 小组详情提供“全部话题”和“全部成员”的原生分页列表，加载失败可重试；条目详情可直接“发讨论”
- 小组、条目话题支持编辑自己的标题与正文；小组 / 条目回复及章节 / 角色 / 人物 / 日志评论支持原生回复、编辑和删除自己的回复。删除整个话题仍转到官网
- P1 讨论正文支持 BBCode 粗体、斜体、颜色、对齐、引用、代码、链接、原位图片和点击展开的剧透遮罩；编辑器提供正文预览
- 社区发帖 / 回复等写操作走 next.bgm.tv P1 + 官方 Turnstile 验证页；私密小组在 P1 成员校验失败时回退官网表单；加组等仍可走内嵌官网
- 社区编辑器提供 BBCode 工具栏；草稿按账号与回复对象自动保存在本机，离开页面或重启后可继续编辑，发送成功后清除；长内容自动折叠，超过 180 天未更新的话题回复前提示
- 手机底部导航与 Windows 宽屏侧栏自适应布局
- 首页采用紧凑的继续追列表，展示封面、已记录进度及操作；保留新番表、每日放送、番会荐和找新番快捷入口，发现页继续使用海报展示
- 长名称支持点按查看完整名称与选择复制；海报标题最多三行、收藏列表两行，条目详情完整换行显示
- 「我的」使用大数字收藏统计面板，突出总收藏并并列展示进行中、已完成，支持大字体和深浅主题
- 点击「我的」统计数字可直达对应状态的全类型收藏；首页和收藏页显示待同步状态，可就地同步或查看失败原因
- 首页可查看全部进行中收藏；发现页保存确认过的最近搜索，收藏页按账号记住筛选与排序，快捷入口不受旧筛选影响
- 番会荐区分检索失败与无匹配结果，部分失败时保留可用推荐并提供重试
- 全应用窄屏适配：页边距 / 标题字号 / 列表密度 / 导航栏标签 / 新番表格子防溢出
- 性能优化：发现结果与长话题懒构建、超长章节分批显示、按屏幕尺寸解码壁纸并减少重复模糊

Bangumi 当前公开 OpenAPI 不提供完整的小组、私信与通知接口。MuBangumi 对社区列表与话题使用 P1 JSON（失败时回退 HTML 解析），并使用短时缓存减少重复请求；如果网站结构发生变化，解析规则可能需要随之更新。

离线能力的覆盖范围、容量限制与验证结果见 [离线体验说明](docs/qa/OFFLINE_EXPERIENCE.md)。首次登录、未缓存内容及短信收发仍需要网络；快照时间表示本机保存时间，不代表修改已同步到官网。

API 的 OAuth 登录可直接调用 next.bgm.tv P1 完成电波提醒与加/删好友。站内短信已改为**原生界面**（收件箱 / 会话 / 发送），通过应用内授权或「我的 → 设置 → Bangumi 账号」保存的官网 Cookie 访问 `bgm.tv/pm` HTML 接口；失败时可回退网页版。小组加入/退出等仍可用内嵌 WebView。退出 OAuth 时会一并清除网站会话。Windows 端需要 Microsoft Edge WebView2 Runtime（Windows 11 和较新的 Windows 10 通常已预装）。

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

登录身份现在与当前凭据共同保存在系统安全存储中，离线恢复不再信任 SQLite 中的旧账号快照。旧版升级后首次需要联网核验账号；凭据仍有效时无需再次网页授权。Windows 的可丢弃缓存使用用户目录下的 `cache-v2`，不导入旧解压目录中的缓存；新番表、草稿和待同步修改保留。

2026-09-11 已撤回夹带开发测试数据的历史 Windows 包。受影响版本及处理记录见 [登录与发布包事件记录](docs/qa/LOGIN_PACKAGE_INCIDENT.md)。从受影响版本升级时，请将干净包解压到全新目录，并先保留旧目录中的个人数据，后续按需备份导入。

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

OAuth 的 Token、刷新凭据与应用配置会在账号验证成功后整组写入系统安全存储；个人 Access Token 不会继承旧账号的刷新凭据，需要到期后手动更换。

登录页分别显示等待授权、验证账号和退出清理状态。等待授权时可取消或切换备用 Token 登录；取消和退出后的旧请求不会覆盖新登录。网络暂时不可用时保留已保存凭据和可用缓存；无法进入主界面时，可点「重新连接已保存的登录」重试。

授权和账号验证提供阶段进度。没有首页缓存时，登录成功后先准备动画收藏，再平滑进入主界面；其他类型和离线修改在后台同步。准备页可点「先进入，后台加载」，也会在等待 8 秒后自动进入，不额外等待全部收藏或封面下载。首页加载失败可直接重试。

应用内 OAuth 授权使用共享 WebView，账号验证通过后会同步保存官网 Cookie，供私信、小组网页等功能复用。手机端在应用内部接收授权回调，无需放开 HTTP 明文网页访问。网页登录成功后会自动保存；从私信进入登录页时自动返回，并继续原先指定收件人的写信操作。

「我的 → 设置 → Bangumi 账号」可管理补充会话。使用个人 Token 或系统浏览器授权时，首次使用网页功能仍可能需要登录一次；之后会复用已保存会话。请使用与应用相同的 Bangumi 账号。Cookie 保存后仍需核验身份；旧版会话升级后会重新核验，不强制清除有效 Token。官网验证码和会话到期后的重登仍然保留。退出会清理网站会话，清理异常时可重试，并阻止下次网页登录直接复用未清理状态。

## 热更新（Shorebird）

应用使用 [Shorebird](https://shorebird.dev) 做 **Dart 代码热更新**（Android / Windows 等）。

- 启动后延迟 2 秒在后台检查（登录界面也可接收修复）；回到前台时检查，30 分钟内不重复请求。自动提醒在登录后以页内提示显示，输入时收起，不自动弹窗。有 Shorebird patch 时后台下载，下次完整启动生效。
- 启动与手动检查合并执行，避免重复下载和重复弹窗。补丁仅在下次完整启动时生效，不会中断当前操作。
- GitHub 正式版支持版本号与构建号比较。点开提示查看摘要与完整 Markdown 公告，可「下载更新 / 明天提醒 / 跳过此版本」。跳过只作用于该 tag；提醒延期持久化 24 小时。网络失败明确提示，不误报为已是最新版。
- Android 自动匹配 ABI，下载后检查大小与 SHA256，安装前核对包名、版本和签名，再交给系统确认。Windows 下载 x64 便携 ZIP 后打开所在目录，用户解压到新目录启动。关闭面板不取消下载，可从“我的 → 检查更新”返回；退出整个应用后重新下载，不支持跨进程断点续传。
- 自动下载要求 GitHub 资产包含 SHA256 digest，并使用 `MuBangumi-版本-build构建号-android-架构.apk` 或 `MuBangumi-版本-build构建号-windows-x64.zip` 命名。缺少匹配包或校验信息时保留发布页入口。正式发布使用唯一的 `v版本+构建号` tag，避免替换已发布版本。
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
.\tool\build_release.ps1 -Target windows -Patch -ReleaseVersion '2.1.1+11'
.\tool\build_release.ps1 -Target apk -Patch -ReleaseVersion '2.1.1+11'
```

`shorebird.yaml` 中 `auto_update: false`，由应用内控制检查与下载，以便展示更新就绪提示。

从 `2.3.1+4029` 起恢复使用 Shorebird 整包基线，Android 分发包含全部 ABI 的通用 APK。内部 build 从 28 提升为 4029，是为了超过旧分架构 APK 的最高 versionCode 4028；后续整包按 4030、4031 递增。`2.3.0+28` 普通 Flutter 包需要先覆盖安装该新基线，之后才能接收匹配的 Dart 热补丁。

发布脚本固定使用 Shorebird Flutter `3.44.7` 创建基线，补丁自动使用服务端记录的对应引擎版本。补丁必须明确指定完整基线版本，避免误发到其他版本。可加 `-DryRun` 只验证构建；不要在补丁中混入原生插件、权限或资源变更。

需要补丁专属公告时，可创建标为预发布的 GitHub Release，tag 使用 `v2.1.1+11-patch.1`（末尾为实际补丁编号），body 填写该补丁说明。应用只读取匹配基线和补丁的公告；公告不存在或网络不可达时仍可应用更新。完整版本公告继续通过正式 GitHub Release 提供。

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

普通 Flutter 发布脚本默认请求图标裁剪并启用调试符号分离。Android APK 默认按架构生成
`app-arm64-v8a-release.apk`、`app-armeabi-v7a-release.apk`、`app-x86_64-release.apk`，
分发时提供适合设备的一份；不要把输出目录中残留的 `app-release.apk` 当作本次产物。
脚本会逐个校验本次预期产物。此选项不改变已有 Shorebird 基线和补丁的编译方式。

```powershell
# 显式指定版本，避免从 pubspec.yaml 中使用过时的构建号
.\tool\build_release.ps1 -Target apk -BuildName 2.2.0 -BuildNumber 25
.\tool\build_release.ps1 -Target windows -BuildName 2.2.0 -BuildNumber 25
```

`release-symbols/` 为每次普通构建保存独立的调试符号和 `build.json` 校验记录，已被 Git 忽略，
必须单独备份且不要放进安装包。排查堆栈时按产物 SHA256 找到对应符号，使用
`flutter symbolize -i stacktrace.txt -d <对应的符号文件>` 恢复可读堆栈。删除符号会影响历史版本崩溃排查。
APK 分架构的 versionCode 包含架构偏移，后续发布需保持各架构版本号递增；普通 Flutter 包不支持 Shorebird 热更新。
体积实测、Windows 图标裁剪限制及验收结果见 [安装包体积优化记录](docs/qa/PACKAGE_SIZE.md)。

## 项目结构

仓库包含 Flutter 主应用、由主应用复用且可独立部署的番键会服务包，以及四个独立的卫星模块：

```text
lib/                      Flutter 主应用（Android / iOS / Windows）
packages/banjian_server/  番键会服务、共享协议模型与网页端；Flutter 通过本地包依赖嵌入
native-android/          独立的 Kotlin + Compose 原生实现（冻结原型，停留 1.7.0）
website/                 项目主页（React + vinext + Cloudflare Workers → GitHub Pages）
tool/recommend_dataset/  推荐模型数据管线与基线（Python，尚未接入 Flutter）
tool/semantic_retrieval/ BGE 中文语义检索原型（Python，尚未接入 Flutter）
tool/                    发布脚本 build_release.ps1 与打包脚本
docs/                    长期体验计划（UX_ROADMAP）与各里程碑验收记录
```

`lib/` 的分层：

```text
lib/
├─ main.dart          # 入口：初始化本地提醒服务后启动 ProviderScope
├─ app.dart           # 根组件：按登录阶段分发准备页 / 登录页 / 主界面
├─ core/              # 基础设施及共享的平台、主题、布局能力
│  ├─ network/       # API 客户端、分页、解析器、线路切换与短时缓存
│  ├─ storage/       # 本地持久化：同步队列、章节快照、草稿、RSS、新番表、偏好
│  ├─ auth/          # OAuth 授权、回调与 Token 刷新、网站会话与 Cookie 桥接
│  ├─ backup/        # 本地备份归档、导入预览计划与 SQLite 仓储
│  ├─ insights/      # 收藏统计、用户对比、公司档案
│  ├─ recommend/     # 番会荐本地规则推荐引擎
│  ├─ social/        # 好友二维码生成、导出与共同好友
│  ├─ notifications/ # 新番表每周更新的本地提醒调度
│  ├─ update/        # Shorebird 热更新与 GitHub Release 检查
│  ├─ layout/        # 宽屏侧栏与窄屏自适应布局
│  ├─ theme/         # Material 3 主题与自定义背景
│  ├─ shortcuts/     # 桌面快捷方式入口
│  └─ widget/        # 桌面小组件桥接与同步宿主
├─ features/         # 逐步按功能拆出的业务模块
│  ├─ auth/application/       # 凭据读写、令牌刷新和过期判断
│  ├─ collection/             # 收藏加载、编辑、章节撤销与数据合并规则
│  ├─ sync/                   # 同步队列模型、上传调度与重试
│  ├─ subject_detail/         # 章节、评论、好友与补充资料加载及展示区块
│  ├─ schedule/               # 新番表搜索、季度选择、拖拽课表与操作菜单
│  ├─ anime_appreciation/     # 番键会原生管理/参与、服务宿主和离线参与记录
│  └─ pm/presentation/        # 邮箱展示、聊天、写信及共用头像和输入组件
├─ models/           # 条目、收藏、章节、社区、私信、RSS、新番表等共享模型
├─ navigation/       # 页面目的地描述与集中路由装配，避免页面之间互相导入
├─ state/            # Riverpod 控制器：会话、同步、新番表、私信、备份、更新…
├─ screens/          # 登录、首页、收藏、发现、社区、详情、新番表、我的
└─ widgets/          # 封面、条目卡片、编辑器、图表等复用组件
```

先从 `lib/state/session_controller.dart` 看登录与页面状态的编排。它保留现有页面接口，将凭据管理委托给 `SessionCredentials`，上传与重试委托给 `PendingSyncController`，收藏加载与编辑分别交给 `CollectionLoader`、`CollectionEditor`。`CollectionReconciler` 提供纯数据合并规则。状态模型和共享 Provider 分别在 `session_state.dart`、`app_providers.dart`。

离线修改仍由 `lib/core/storage/bangumi_sync_store.dart` 先写入 SQLite，再更新界面；上传时机、账号请求保护与重试由 `features/sync/application/pending_sync_controller.dart` 负责。凭据、收藏、同步、搜索和详情页读取模块不依赖页面或全局会话控制器。详情页、新番表和短信邮箱保留在 `screens/` 作为页面入口，独立展示区块与加载逻辑已迁入对应的 `features/` 目录；新番表操作菜单仍通过现有 Provider 连接进度、提醒和 RSS。短信聊天/写信界面在 `features/pm/presentation/`，继续复用原有邮箱、草稿控制器与网络服务，原页面文件转导出公开入口。

边界与验证记录见 [会话职责拆分](docs/architecture/SESSION_REFACTOR.md)、[收藏加载与编辑拆分](docs/architecture/COLLECTION_REFACTOR.md)、[详情页拆分](docs/architecture/SUBJECT_DETAIL_REFACTOR.md)、[新番表拆分](docs/architecture/SCHEDULE_REFACTOR.md) 和 [短信与详情请求收尾](docs/architecture/PM_AND_SUBJECT_REQUESTS_REFACTOR.md)。

社区与私信网络服务由 `state/service_providers.dart` 按 ProviderContainer 创建和释放，账号访问协调器只安装本作用域的认证回调。社区持久缓存按账号命名，收藏快照携带完整性、加载类型和来源总量；不完整快照不会被统计与导出当成完整收藏。番键会凭据留在系统安全存储，待确认命令与可丢弃快照分开保存在 SQLite。

2026-09-19 的[架构审查](docs/architecture/ARCHITECTURE_REVIEW_2026-09-19.md)及[修复与验收记录](docs/architecture/ARCHITECTURE_FIXES_2026-09-19.md)说明这些边界、迁移策略和验证范围。CI 运行 `python tool/verify_architecture.py --self-test`，阻止循环依赖和全局认证服务回归。

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
