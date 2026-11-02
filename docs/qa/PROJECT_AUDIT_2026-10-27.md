# MuBangumi 全仓缺陷与应用体验审计

日期：2026-10-27。基于审计开始时的未提交工作区，三个 GPT-6.1-sol 子代理分别检查数据与会话、Flutter 界面、服务端与网站，主代理复核平台集成、维护脚本和统一验证。

本轮确认五类功能问题，涉及四个生产文件：私信重复入队、新番搜索键盘遮挡与空状态溢出、番键会管理页恢复失败、研究采集器错误分类、HTTP 成功统计失真。全仓在线审计又发现网站依赖安全问题，一并处理。没有增加客户端依赖、全局服务或新的重试框架。既有改动、凭据和运行数据保留；未提交或发布。

## 已修复问题

优先级按本项目的实际影响判断：P1 为可能造成重复发送或数据持续遗漏，P2 为局部流程不可用或统计错误。

| 优先级 | 问题与触发条件 | 修复后行为 | 主要位置 |
| --- | --- | --- | --- |
| P1 | 相同草稿在第一次本地入队完成前再次提交，第二次事务取得更新后的 revision，生成两个相同的私信任务 | 同一编辑版本共享正在进行的入队操作；期间输入的新消息仍独立保存 | `lib/state/pm_draft_controller.dart` |
| P2 | 新番搜索自动弹出键盘，但底部弹层没有扣除键盘区域；缩小区域后空状态又发生布局溢出 | 弹层避开键盘，空白/错误状态可滚动；清空按钮提供文字提示 | `lib/features/schedule/presentation/schedule_search_sheet.dart` |
| P2 | 番键会管理页打开或创建活动后，首次状态请求失败，只有活动 ID 的半加载对象被当作完整快照渲染 | 展示恢复提示，继续已有重连流程，收到完整快照后恢复管理界面 | `packages/banjian_server/web/app.js` |
| P1（研究模块） | 429 重试耗尽或 401/403 等错误被当作永久不可用，条目被后续续采和导出排除 | 仅保留既有的 404 及明确消失的 410 为不可用；临时错误保留后续恢复机会 | `tool/recommend_dataset/src/http_client.py` |
| P2（研究模块） | HTTP 200 返回无效 JSON，在解析前已计一次成功，解析失败又计一次失败 | JSON 解析成功后才增加成功计数 | 同上 |

私信修复仅合并本地入队，没有重放结果不确定的 POST，也没有改变 P1 写入通道、网站 Cookie 或账号所有权规则。研究模块修复不改变客户端推理能力。历史研究数据库中已被误标为永久失败的记录没有自动迁移，本轮未读取或改写这些数据。

网站依赖修复涉及 `website/package.json` 和 `website/package-lock.json`：`undici 7.29.1 → 7.30.1`、`zod 4.4.3 → 4.6.7`、`fast-uri 3.1.8 → 3.1.9`。首轮在线审计的两个未缓解高危来自 undici 和 zod；fast-uri 的中低危也通过同主版本更新消除。锁文件仅三个包条目变化，没有增加或删除包，保留已有 braces 补丁与其他依赖版本。没有运行无差别 `npm audit fix` 或新增告警豁免。

修复版本依据：[undici 高危公告](https://github.com/advisories/GHSA-xjj6-f33q-929c)、[Zod 内存耗尽公告](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5)、[fast-uri 3.1.9 发布记录](https://github.com/fastify/fast-uri/releases/tag/v3.1.9)。这是依赖审计发现，不代表已经在本应用中复现了公网攻击；更新后的构建与在线审计结果见下文。

## 检查覆盖

| 区域 | 本轮检查内容 | 判断边界 |
| --- | --- | --- |
| 数据、会话与异步 | API/cache 失效、网站会话、凭据域、CommunityWriteClient、草稿、发送队列、邮箱、联系人、通知、RSS、用户偏好和 SQLite 串行操作 | 使用合成数据回归；未做真实账号发信/发帖 |
| Flutter 体验 | 搜索、导航、好友账号切换、分享/封面弹窗、更新提示、配置迁移及条目元信息 | 键盘用 widget 几何约束验证；不等同于真实移动设备体验 |
| 番键会 | HTTP/WS 认证、来源校验、封面来源、匿名导出、浏览器生命周期和恢复 | 本地协议/服务测试；未做现场多设备鉴赏 |
| 网站 | Worker、静态发布、演示组件、类型/风格及依赖安全 | 构建与浏览器结果见验证记录；无云端部署 |
| 研究模块 | 推荐采集错误处理、恢复机制及语义检索回归 | 不运行真实采集，不加载模型推理，不更改研究数据 |
| 平台与维护 | Android 相册/分享/安装入口、iOS 相册通道、Windows 平台集成、架构依赖、工具版本、打包隐私和发布来源记录 | 冻结的 `native-android/` 原型未修改；平台执行结果独立列出 |

没有把未复现的怀疑当作 bug。例如私有命名构造参数在项目固定 Dart 3.12 下合法，相关候选经验证后保留原实现。此次检查覆盖上述区域及全仓自动验证，不意味着逐条运行所有设备与业务组合。

## 与官方做法的对照

| 主题 | 官方依据 | 对本项目的处理 |
| --- | --- | --- |
| 异步提交与 HTTP 重试 | [Dart 并发](https://dart.dev/language/concurrency)、[RFC 9110 幂等方法](https://www.rfc-editor.org/rfc/rfc9110.html#name-idempotent-methods) | 单 isolate 仍需处理异步交错；同草稿重复入队合并，不确定的非幂等消息发送保持人工核对 |
| 键盘、弹层与可访问性 | [Flutter viewInsets](https://api.flutter.dev/flutter/widgets/MediaQueryData/viewInsets.html)、[底部弹层](https://api.flutter.dev/flutter/material/showModalBottomSheet.html)、[可访问性](https://docs.flutter.dev/ui/accessibility) | 输入弹层根据键盘区域布局；保留可滚动内容，图标操作提供名称 |
| 离线与数据边界 | [Flutter 离线优先](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)、[架构建议](https://docs.flutter.dev/app-architecture/recommendations) | 继续利用已有仓库、缓存和同步状态；避免为每个界面新增数据层或通用封装 |
| 断线恢复与状态完整性 | [MDN WebSocket 客户端](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_client_applications) | 恢复期可以缺少完整快照；渲染不应抛错阻断连接恢复 |
| 限流与失败分类 | [RFC 6585 429](https://www.rfc-editor.org/rfc/rfc6585.html#section-4)、[RFC 9110 410](https://www.rfc-editor.org/rfc/rfc9110.html#name-410-gone) | 耗尽本次重试不代表永久删除；404 的旧采集策略暂时保留，避免扩大改动 |
| 性能与系统能力 | [Flutter 性能建议](https://docs.flutter.dev/perf/best-practices)、[Android MediaStore](https://developer.android.com/training/data-storage/shared/media) | 保留现有懒加载、图片尺寸限制和原生媒体写入方式；没有性能测量证据时不进行推测性重构 |

上述为官方文档原则与本项目实现的对应分析，不是对流行客户端的市场排名或横向性能测评。

## 视觉与交互复核

额外运行既有首页、消息反馈和个人空间测试，开启 `UX_SCREENSHOTS=true`，12 项通过；实际查看 9 张合成页面截图，保存在 `.dart_tool/audit-2026-10-27/visuals/`。覆盖 320px 手机首页、360px 消息页、1400px 桌面首页，以及 1.0/1.8 字号下的空间和封面弹窗。图片为测试夹具，不代表真实封面加载或线上账号。

- 消息页深浅主题的发送队列入口、待处理角标和同步/发布状态可见，未观察到相互遮挡。
- 个人空间在 1.8 倍字号下的昵称与签名换行，封面弹窗的关闭和保存操作保持可见。
- 320px 首页的四个快捷入口在大字号下变为两行，保持可达；同时热力图明显增加首屏高度，“继续追”落在首屏下缘。这是信息优先级问题，可考虑将热力图默认收起或移到继续追之后，暂不替用户改变现有首页布局。

## 验证

固定工具链由 `tool/toolchain.ps1` 选择：Flutter 3.44.7、Dart 3.12、Node 22.23.2；Python 使用三个项目各自的固定环境。没有升级全局 SDK 或改变 Shorebird 基线。

针对性回归：私信发送队列 11 项，其他草稿/邮箱/联系人/缓存/旧账号响应 111 项，新番搜索 9 项，推荐采集 31 项，语义研究 43 项，网站安全测试 12 项，以及浏览器协议断言和 4 项生命周期测试通过。网站 lint/typecheck 及修改处静态分析通过。这些数字有部分会再次包含在统一验证中，不能相加作为独立覆盖数量。

统一验证命令：`pwsh -NoProfile -File tool/verify_all.ps1 -Mode Full -WindowsSmoke`。

首轮全区域 Full 共 28 个检查步骤：27 项通过，网站安全审计失败。随后仅更新网站的三项依赖，运行 `./tool/verify_all.ps1 -Mode Full -Areas @('website','tools')`，13 个步骤全部通过。未因网站依赖更新重复运行无关的 Flutter/原生测试，以下结果分别对应两轮记录。

| 验证项 | 实际结果 |
| --- | --- |
| Flutter 静态分析 / 全量测试 | 无问题 / 1,926 项通过 |
| Windows 安全存储与 SQLite | 1 项通过；其中移动 WebView 用例在 Windows 明确跳过 |
| Windows WebView | 独立资料目录、本地 HTML 冒烟通过 |
| Windows / Android 构建 | Windows Debug、Android arm64 Debug APK 均通过 |
| 番键会 | Dart 分析、43 项服务端测试、CLI bundle、浏览器协议与 4 项生命周期测试通过 |
| 网站更新后 | lint、typecheck、SSR 构建/页面测试、GitHub Pages 静态构建/页面测试、6 项桌面/手机浏览器测试通过 |
| 网站安全 | 原始 npm audit 所有严重级别均为 0；已有补丁安全回归 12 项通过 |
| Python | 推荐数据 198 项、语义研究 43 项、发布镜像 11 项通过 |
| 架构与维护 | 架构、验证码桥接、固定 Node、Windows 包隐私、发布构建、工作区清理、仓库隐私及来源记录检查均通过 |

原始记录：[首轮全区域 Full](../../.dart_tool/verification/20261026-193310-feab9465/results.json)、[网站与工具 Full 复验](../../.dart_tool/verification/20261026-194304-33354287/results.json)。两个批次均没有运行期间源码漂移失败。记录绑定各自执行时的内容指纹；复验完成后仅整理本报告和文档导航，未再修改生产代码、依赖或测试。工作区仍包含审计前的未提交改动，这些结果不是发布许可。

尚未执行：Android/iOS 真机或模拟器冒烟、iOS 构建（本机是 Windows）、真实账号验收、原生文件交换、系统提醒送达、更新安装、现场局域网与云部署。自动化通过不代表这些项目通过。

## 后续体验工作

1. 优先做真实移动设备的键盘收起/弹出、横屏及大字号验收；本轮修复的是已复现的竖屏键盘遮挡，不能用 widget 测试推断全部输入法和设备通过。
2. 为真实账号准备专用收件人/小组后，再验收切账号、私信送达、网站挑战和离线补传。现有合成回归可覆盖状态机，不能替代线上服务兼容性。
3. 若研究数据曾遇到限流，后续可先统计误标记录，再定向恢复采集；不要全库重写或自动清空永久失败记录。
4. 性能优化先用代表性设备和页面测量帧耗时、内存与冷启动，再改热点；本轮不声称帧率、包体或运行内存已有提升。

详见分报告：[数据与会话](audit-data-2026-10-27.md)、[Flutter 界面](audit-ux-2026-10-27.md)、[服务端与研究模块](audit-services-2026-10-27.md)。
