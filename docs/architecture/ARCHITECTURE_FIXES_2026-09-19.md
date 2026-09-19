# 架构修复与验收记录

对应 [2026-09-19 架构审查](ARCHITECTURE_REVIEW_2026-09-19.md)，基线为 `v2.3.0+28 / 3d345e8`。本次在现有 Flutter + Riverpod 与独立 Dart 服务架构内修复审查列出的六项问题；没有改变已发布版本、推送代码或发布新 Release。

## 修复结果

| 发现 | 实现 | 关键验证 |
| --- | --- | --- |
| F1 迟到响应覆盖新状态 | 参与端按请求序号、账号/活动代次、服务端 revision 和 WebSocket 身份接收结果；旧错误不再把新连接标为离线。管理端使用相同版本约束；serverEpoch 区分服务重启。 | 永久测试覆盖旧 HTTP 成功、旧 HTTP 失败、WebSocket 抢先更新、切换活动后的旧响应。 |
| F2 全局认证服务与缓存归属 | CommunityService / PmService 由 ProviderContainer 创建、注入、释放；账号协调器只安装本作用域回调。账号变化重建导航栈，社区缓存按账号命名，旧无归属缓存升级时丢弃。 | 两容器互不影响、销毁不撤销另一容器回调、缓存隔离、退出与重登回归。 |
| F3 循环依赖 | 页面目的地与页面构造在 navigation 中分离，品牌组件与根组件分离，私信草稿模型与存储实现分离。测试使用和应用一致的路由装配入口。 | 247 个主应用 Dart 文件的 import/export 图无环；新增 CI 边界检查，禁止应用层反向引用页面和全局认证服务。 |
| F4 收藏快照被当成完整集合 | 快照增加完整性、来源总量、已加载类型、保存时间。4000 条保留上限触发 partial；旧快照标为 unknown。统计与导出明确数据范围。 | 超上限裁剪、旧格式、空完整集合、局部编辑、收藏导出与统计回归。 |
| F5 活动数据与快照无限扩张 | 服务端 schema 4 分离元数据、成员、评分、短评和同步版本；高频写入不更新宽元数据行。128 项变更日志支持轮次增量；通知合并、评论预览/游标读取、流式导出。客户端凭据、事务命令日志和有上限的快照缓存分离。 | 旧数据库/安全存储迁移、跨连接元数据刷新、热写入禁止更新元数据的触发器断言、评论权限和导出、50 客户端负载。 |
| F6 动态协议与静默错误 | 共享 RoomSnapshot / RoundSnapshot / RoomCommand / RoomCommentsPage 校验协议边界；网页端对应协议模块共用测试样本。输入损坏明确报错；数据合并验证基线，缺失时重取完整状态。 | Dart 与 Node 共用协议样本；最大内容快照字节预算；浏览器交互、撤回公开内容、离线队列回归。 |

## 数据与兼容性

活动数据库迁移在事务内完成，旧 JSON 格式先创建一次 `.pre-v2.sqlite`；中间分表版本升级创建 `.pre-v4.sqlite`。成员身份、已确认评分、隐藏短评及操作回执均保留。管理操作仍以 `version` 比较冲突，评分不干扰管理版本；所有可见变化另以 `revision` 排序。

原生客户端新增 `banjian/participation.sqlite`。参与 Token 和完整邀请链接仍在系统安全存储，命令和草稿写入 SQLite 后才发送。迁移在所有身份凭据和事务写入成功后删除旧安全存储记录；失败可以重试。历史身份和待确认命令不因缓存淘汰而删除，旧活动按需读取。快照最多 8 场、合计 16 MiB，保存节流，大块 JSON 编解码交给后台 isolate。

服务协议继续标为 v1，并声明增量能力。未请求失效通知的旧客户端仍接收完整角色投影；新版收到分数/短评更新后获取变动轮次，结构变化直接接收完整投影。增量日志不足或服务重启时回退完整同步。每轮快照预览 20 条短评，原生与网页端都可查看全部短评；单次分页至多 100 条。完整 JSON/CSV 导出使用一致性读事务和流式输出。常规响应按 UTF-8 字节限制为 8 MiB，最大 100 轮、500 成员的边界样本通过该预算。

旧社区缓存仅清理可重新获取的数据，不删除收藏修改队列、私信草稿或凭据。收藏依旧保留 4000 条离线快照上限，但不再隐瞒不完整状态。恢复到旧软件如需回退活动数据库，应使用迁移前备份，不能把新表结构当作旧数据库直接使用。

## 验证

- `flutter test --no-pub --reporter expanded`：1145 项全部通过。
- 收尾新增评论权限回归测试：公开规则变化立即清空原生历史页、撤销旧请求、重置游标；与本地存储和缓存隔离测试一起运行，8 项通过。该新增用例不包含在前述 1145 项中。
- `flutter analyze --no-pub`：无问题。
- 独立服务 `dart test`：33 项全部通过；`dart analyze` 无问题。
- `node packages/banjian_server/test/room_protocol_test.cjs`：通过。
- `python tool/verify_architecture.py --self-test`：通过。
- `tool/qa/banjian_browser_check.py`：15 种响应式场景通过，包括单屏布局、主题切换及实时操作；JavaScript 错误为空。
- `tool/qa/banjian_pagination_check.py`：123 条短评分为 50/50/23 三批；参与者新增后导出完整 124 条；管理端关闭评论公开后，参与端只保留自己的短评。

负载数据见 [load-delta.json](../qa/architecture-fixes/load-delta.json)，浏览器结果见 [browser-results.json](../qa/banjian-implementation/browser-results.json)。负载使用 Windows 回环地址、临时数据库、50 个参与身份及 10 个轮次；测量包括写入确认与该客户端收到自身状态更新，不能等同于真实热点的网络延迟。

最终两分钟负载运行 124 秒，确认 1200 次写入，50 个身份评分均保留；确认与自身状态更新 p95 为 196.611 ms，最大 211.843 ms，应用层接收数据合计 4,991,576 字节。测试同时段存在构建等本机任务，不用于推断不同版本间的严格性能百分比。

本轮没有用用户的真实账号执行发帖、私信、评分等写入，没有手动迁移真实活动数据库。尚未进行真实手机热点、Android 锁屏保活、长达数小时的活动或公网部署验证。网站、冻结的 Kotlin 原型和 Python 推荐原型不在本次六项修复范围内。

## 构建

最终源码已完成以下本地构建，均使用普通 Flutter/Dart 构建，没有推送 Shorebird 补丁：

- Windows：`build/windows/x64/runner/Release/mubangumi.exe`；已重新打开，进程响应正常。运行时需保留同目录插件和 data 目录。
- Android：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`、`app-armeabi-v7a-release.apk`、`app-x86_64-release.apk`，分别约 34.2 / 30.7 / 36.8 MB。不要使用该目录残留的旧 `app-release.apk`。
- 独立服务：`packages/banjian_server/build/bundle`，包含 SQLite 动态库和四个网页文件；编译产物的 HTTP 启动、静态资源与进程重启后的数据持久性验证通过。

构建仍使用本地版本号 `2.3.0+28`，作为本轮修复测试包，尚未创建新的发布版本。已发布的 `dist/2.3.0-build28` 产物保持原样。校验记录见 [builds.json](../qa/architecture-fixes/builds.json)，测试摘要见 [verification.json](../qa/architecture-fixes/verification.json)。调试符号独立保存在被忽略的 `release-symbols`，未放入安装包。

构建日志包含现有插件的 Kotlin Gradle 迁移提示，但本次构建成功；没有为消除兼容性提示而升级整组插件。
