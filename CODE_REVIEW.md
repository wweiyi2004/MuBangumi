# MuBangumi v1.5.0 代码审查报告

> 生成日期：2026-08（审查伴随 v1.5.0 发布）
> 状态：**已修复 H1/H2/H3、M1-M7、M10-M17（Windows 部分除外）、L1/L3/L4/L5/L7/L8/L11/L14/L15/L17/L18/L19/L23/L25/L27**；H4（PKCE）待服务端支持确认后评估。
> 审查方式：5 个并行分组审查（core 安全/网络层、社交与私信页面、内容与社区页面、组件/状态/模型、平台配置与构建）+ 全量静态检查与测试执行 + 逐条交叉核实。

## 范围与自动化检查结果

- 覆盖 lib/ 全部 100 个 Dart 文件（约 37k 行）、test/ 44 个测试文件、Android / Windows / iOS 工程、构建脚本、Python 推荐数据集工具（tool/recommend_dataset/）。
- flutter analyze：**0 问题**。
- flutter test：**179/179 全部通过**。
- 全库无 TODO/FIXME；无硬编码密钥；git ls-files 证实 oauth.local.json、key.properties、*.jks、build 产物均未入库。
- 凭据链路安全基线核实：token/refresh_token/Cookie 走 flutter_secure_storage；日志无凭据明文；OAuth loopback 回调 + Random.secure state + 单飞刷新（_refreshInFlight）；外网全 HTTPS。

## 总体评价

代码质量在同类第三方客户端中属**中上水平**：JSON 解析全量类型防御（无裸 as 强转崩溃点）、竞态防护（generation/inFlight/requestId）体系一致、登出级联清理完整、HTML 经 package:html 纯文本化规避注入。**未发现 Critical 级问题**（无凭据泄露、无确定性崩溃、无数据丢失路径）。主要短板是同一套健壮性标准未贯彻到所有控制器（schedule/rss 缺少错误处理与竞态守卫）、错误可见性（空 catch 把失败伪装成暂无数据）、以及少量安全设计债（客户端 client_secret、WebView 导航白名单、iOS 权限声明）。

---

## High（建议优先修复）

### H1. iOS 缺少 NSCameraUsageDescription，扫码直接崩溃
- ios/Runner/Info.plist：无任何 NSCameraUsageDescription 键。
- lib/screens/friend_qr_scan_page.dart:46 使用 MobileScanner，且 iOS 判定支持相机；iOS 首次访问相机时缺少该键会**直接终止进程**。
- 建议：plist 增加 NSCameraUsageDescription（如「用于扫描好友二维码」）。

### H2. 冷启动 _bootstrap 无错误处理，安全存储故障时永久卡启动页
- lib/state/session_controller.dart:90,113-119：构造器 unawaited(_bootstrap())，开头 Future.wait([...5 个 secure-storage 读取]) 无 try/catch。Android 密钥库/Keychain 异常会变成 unhandled async error，phase 永远停留在 booting，首屏无限转圈、无重试入口。
- 建议：包 try/catch，失败回落 signedOut + 错误提示，或提供「重试」按钮。

### H3. OAuth 登录双击竞态：第二次授权失败会重置会话状态
- lib/screens/auth_screen.dart:49-73：守卫只在 _startOAuth 开头读一次 isRefreshing，随后 await readOAuthConfig() 形成异步窗口；双击会并发两次 signInWithOAuth → 第二次 HttpServer.bind(127.0.0.1:43927) 抛 SocketException → session_controller.dart:221-229 的 catch 用 SessionState(phase: signedOut, ...) **整体重置状态**，与仍在进行的首次授权并存，用户看到错误提示但授权其实还在继续。
- 建议：在 signInWithOAuth 入口做同步的 in-flight 守卫（原子置位），或对「端口被占用」单独提示而不重置状态。

### H4. 公开客户端内置 client_secret 且无 PKCE（安全设计债）
- lib/core/auth/oauth_builtin.dart:17-25 + tool/build_release.ps1：secret 经 --dart-define 编译进二进制，APK 可被反编译提取，冒充本应用 OAuth 客户端。README 已承认此风险，但应正视：公开原生客户端应迁移 **PKCE**（S256），客户端不再持有 secret；并考虑轮换当前 secret。

---

## Medium

### M1. schedule_controller 无代际守卫，快速切换季度结果错位
- lib/state/schedule_controller.dart:48-71：load(season) 写回结果时不校验当前 season，慢的旧请求会覆盖新请求（表头新季/内容旧季，knownSeasons 还会塞回旧季）。双击切换、删除后立即建新季均可触发。
- 建议：引入 _loadGeneration 计数，过期结果丢弃（参照 session_controller 模式）。

### M2. schedule_controller 本地存储读写无任何错误处理
- schedule_controller.dart:50-53,85,241-248：load/_persist/deleteCurrentSeason/addSubject 等直接 await _store.*；sqflite 报错即 unhandled async error，loading 永久 true。
- 建议：统一 try/catch + message 反馈，与 session/rss 控制器对齐。

### M3. rss_controller 写操作与 reload 缺错误处理
- lib/state/rss_controller.dart:54,157-167,281-289：构造期 reload() unawaited，deleteSource/unbind/unbindSubject/markItemRead 裸 await + reload。
- 建议：try/catch 并落 state.message。

### M4. rss_controller.bindSubject 把任意 DB 错误误判为 UNIQUE 冲突
- rss_controller.dart:128-154：catch 一切异常后默认按「已存在绑定」处理并再次 upsert，掩盖真实故障（表损坏/写失败）。
- 建议：先查 listBindings 决定 insert/update，或让 store 返回可区分的冲突错误。

### M5. 标「看过」自动补完章节失败被静默吞掉
- session_controller.dart:696-698：changeCollection 中 type==done 的章节补完整段 catch (_) {}；收藏状态已改但进度未补完时用户无从得知。
- 建议：失败信息并入返回消息（「已保存，但章节进度补完失败…」）。

### M6. website_login_screen 的 FutureBuilder 内联 future，已保存 Cookie 从未注入
- lib/screens/website_login_screen.dart:18-27：future: loadWebsiteSeedCookies() 每次 build 新建 Future；首帧 snapshot.data == null → 以空 Cookie 初始化 CommunityWebScreen，其 initState 只注入一次 widget.seedCookies 且无 didUpdateWidget。结果：同步网站登录页**永远不带已保存会话**打开（对比 pm_page.dart:153、community_group_screen.dart:81 的正确写法：先 await 再 push）。
- 建议：改为 initState 中加载，或先 await 再构建 CommunityWebScreen。

### M7. pm_page 线程切换无请求守卫，可能回复到错误线程
- lib/screens/pm_page.dart:720-747,842-845：_load() 无 requestId/generation 守卫，快速切换线程 chip 时旧响应覆盖新线程内容；_send 用 detail.form 回复，可能把回复发到用户以为已离开的线程。
- 建议：加 _threadLoadGeneration，过期响应丢弃。

### M8. 详情页 Future.wait 一损俱损
- character_detail_screen.dart:50-54、person_detail_screen.dart:68-72、subject_detail_screen.dart:181-185、score_trends_page.dart:48-51、collection_comparison_page.dart:46-52：多个独立请求共享一个失败状态，任一失败整页报错。
- 建议：各自 try/catch，失败区块单独降级+重试。

### M9. subject_detail 多处空 catch，失败伪装成「暂无数据」
- subject_detail_screen.dart:177-196,199-214,216-258,260-293,734-749：_loadMeta/_loadTopics/_loadComments/_loadFriendStatuses/_reloadEpisodeWatchState 全部空 catch，无错误提示无重试（与 _loadScoreHistory/_loadMoegirl 的带错误处理写法不一致）。
- 建议：统一为「错误文案 + 重试按钮」。

### M10. _CourseTable 重复 itemsOn + 整表 eager 构建
- schedule_page.dart:1006-1009,1109,1175-1189：itemsOn() 是每次过滤+排序的 O(n) 操作，build 中按 7 天 × 每格反复调用；整表 SingleChildScrollView + Column 一次性构建全部单元格（含 Draggable + 网络图）。
- 建议：build 开头按 weekday 预分组一次；网格改懒构建。

### M11. dio onError 拦截器 401/429 分支为死代码
- bangumi_api.dart:36-50（同 netaba_api.dart:37-50）：if (data is Map) 排最前，bgm.tv 4xx 均为 JSON body，导致 401/429 专属中文文案永不触发，用户看到服务端英文 description。
- 建议：先按 statusCode/error.type 判定，再 fallback 解析 body。

### M12. getUserCollections 带 maxItems 时不排序
- bangumi_api.dart:186-195：maxItems != null 时在 sort 前提前 return，API 原始顺序；user_profile_page.dart:243 拿到的列表未按 updatedAt 降序。
- 建议：先排序再截断。

### M13. community_service 内存缓存无上限、无过期回收；token 刷新时整体清空
- community_service.dart:55-57,70-78：_jsonCache/_htmlCache/_friendsCache 有 TTL 但过期条目不回收，长期使用内存增长；每次 setAccessToken 整体清空造成不必要的重复请求。
- 建议：写入时顺带清理过期键或改 LRU；token 刷新不清空。

### M14. community_service 重试策略不一致
- community_service.dart:759-762 的 _getJson 内联 shouldRetry 漏掉 429，_getJsonList 用的 _shouldRetry 含 429。
- 建议：统一复用 _shouldRetry。

### M15. RSS 日期解析忽略时区
- rss_fetcher.dart:206-240：自定义 HttpDate.parse 忽略 +0800 等时区偏移一律按 UTC，非 UTC 源时间错位最多 ±12 小时（影响「新」判定与排序）。
- 建议：按 RFC 822 解析时区。

### M16. 内嵌 WebView 无导航域白名单
- community_page.dart:405-407：JavaScriptMode.unrestricted + 注入会话 Cookie，但 NavigationDelegate 没有 onNavigationRequest 域检查，社区帖子外链可在无地址栏的内嵌浏览器中打开任意站点（钓鱼风险）。
- 建议：非 bgm.tv/bangumi.tv 域跳转改 launchUrl 系统浏览器。

### M17. build_release.ps1 缺少产物存在性校验
- tool/build_release.ps1:72-74：只检查 exit code，未断言 apk/aab/exe 真实生成。
- 建议：按 Target 断言产物路径存在且非空。

---

## Low

- L1. DropdownButtonFormField.value 已弃用仍在使用并被 ignore 掩盖（schedule_page.dart:335,350、rss_sheets.dart:283）；改用 initialValue；顺带把 rss_sheets.dart:244 的 build 内 _sourceId ??= 挪到 initState。
- L2. bangumi_api.dart:68,313-316 条目详情缓存永不失效（仅换线路时清空），随会话无限增长；建议 TTL/LRU。
- L3. rss_fetcher.dart:111,134 用 String.hashCode 当持久化去重 GUID，跨版本/碰撞风险；建议内容摘要。
- L4. rss_fetcher.dart:82-97 非法 XML 抛原始英文异常直接进提示；建议包装中文文案。
- L5. website_cookie_bridge.dart:218,241：replaceAll 去双引号会破坏含引号的 cookie 值；endsWith(bgm.tv) 会把 notbgm.tv 误归一化；建议精确后缀 .bgm.tv 与类型化取值。
- L6. bangumi_support.dart:430-488 正则解析评论区 HTML 脆弱；优先结构化接口，正则仅兜底。
- L7. UA 版本漂移：9 处 4 个版本（bangumi_api/community_service/netaba 为 1.1.0，oauth/pm 为 1.2.0，moegirl 为 1.3.0，rss_fetcher 为 0.4），应用实际 v1.5.0；建议单一常量注入。
- L8. session_controller.dart:103,342-345 _collectionsInFlight 死代码（只写不读）。
- L9. update_controller.dart:140-145 restartApp() 直接 exit(0)，跳过 Flutter 拆除/落盘；移动端建议平台推荐方式。
- L10. episode_grid_sheet.dart:25-27 点格子面板关闭后无条件全量刷新收藏（未改动也刷新）；建议回传 dirty 标志。
- L11. community_composer.dart:73-84 Turnstile 验证期间 _submitting 未置位，连点可拉起多个验证对话框；建议进入 _submit 即锁按钮。
- L12. oauth_authorization_dialog.dart:73-87,172-176 dispose 与 _initialize 并发执行 _disposeController，窄竞态下可泄漏新创建的 WebView controller；建议 _disposed 标志收敛。
- L13. theme_controller.dart:21,33、background_controller.dart:109,115 存储失败静默吞掉；建议 debugPrint 留痕。
- L14. profile_page.dart:74、subject_detail_screen.dart:1526 characters.first 无空串保护，脏数据可致崩溃；建议 isEmpty 保护。
- L15. subject_detail_screen.dart:1731-1735 _ExpandableText 每次 build 新建 TextPainter 且不 dispose；建议复用/释放。
- L16. collection_stats_page.dart:96-107 移动端导出到应用私有目录且无分享出口（share_plus 已在依赖中未用）。
- L17. schedule_page.dart:414-420,486 搜索回车提交未取消 400ms 防抖，产生重复请求。
- L18. subject_detail_screen.dart:137 错误文案未统一剥 Exception: 前缀，与其他页不一致。
- L19. user_profile_page.dart:112-119,208-222 重复 _loadFriendship：_loadAll 的 Future.wait 已调用一次，_loadProfile 成功后（216 行）又 await 一次，非本人主页一次进入发出两次 isFriend 请求。
- L20. user_profile_page.dart:217-221 _loadProfile 空 catch，仅保留 seed，网络失败无法与「加载中」区分，无重试入口。
- L21. pm_page.dart:58-85 收件箱/发件箱仅加载第 1 页（PmService 默认 page=1），无加载更多，会话多的用户看不到第 1 页之后的会话。
- L22. notify_page.dart:43-53,349-350 通知仅拉单页（limit 40），头部显示「共 N 条 · 显示 40 条」却无加载更多入口，旧通知不可达。
- L23. friend_qr_scan_page.dart:38 + core/social/friend_qr.dart:33-47 扫码页「从图片识别」在主线程同步 img.decodeImage + QRCodeReader().decode，大图可致明显卡顿/ANR；建议 compute/isolate 解码或先压缩。
- L24. friends_page.dart:131-135 _loadMore 失败静默：错误分支要求 _error != null && _friends.isEmpty，加载更多时列表非空，失败既不提示也不可重试。
- L25. friend_collections_page.dart:8-18 FriendCollectionsPage 全仓库无任何引用，属遗留死代码，建议删除。
- L26. android/key.properties.example 用绝对路径示例，与 rootProject.file() 相对解析不一致。
- L27. .gitignore 缺 **/*.keystore（仅 *.jks），android/app/upload.keystore 有误提交风险。
- L28. analysis_options.yaml 未启用 unawaited_futures/discarded_futures/avoid_empty_catches，异步错误吞噬无静态兜底。
- L29. 仓库卫生：review_diff.txt（上次审查遗留 diff）与 bgm_v0.yaml（API spec）未跟踪未忽略，建议入库或加 .gitignore。

---

## 亮点

1. **OAuth 安全闭环**：loopback-only 绑定 + Random.secure() 24 字节 state 严格比对 + 3 分钟超时 + 主动取消；刷新用 _refreshInFlight 单飞，并发 401 不触发多次 refresh。
2. **登出级联清理**：token、网站 Cookie（WebView jar）、内存缓存、快照一体清理，并处理「在途保存写回旧会话」窗口。
3. **JSON 解析零崩溃**：模型层全面 _int/_double/_string/_map 防御，无裸 as 强转。
4. **HTML 安全渲染**：外部 HTML 经 package:html 纯文本化（_plainText/_stripHtml），PM/社区内容无脚本执行面。
5. **竞态防护体系一致**：无限滚动 _requestId + _loadingMore 防串页防重入；收藏同步 generation 守卫 + 乐观回滚。
6. **资源管理到位**：审查到的 controllers/subscriptions/定时器均在 dispose 释放；图像导出 finally 释放 ui.Image。
7. **安全 UX**：第三方反代二次确认 + 风险说明；Turnstile token 占位符校验；社区内容本机屏蔽 + 临时展开。
8. **测试扎实**：44 个测试文件、179 个用例覆盖模型/解析器/控制器/服务核心逻辑；Python 数据集工具限速、退避、盐化匿名、全数据 gitignore，规范程度高。

---

## 修复优先级建议

1. **立即**：H1（iOS plist 加相机描述）、H2（bootstrap try/catch）、M6（网站登录 Cookie 注入——影响现有功能正确性）。
2. **本版本收尾**：H3（登录竞态守卫）、M1/M2/M3/M4（schedule/rss 控制器健壮性）、M5（补完失败反馈）、M7（PM 线程守卫）。
3. **下一版本**：H4（PKCE 迁移评估）、M8-M17（详情页降级、性能、错误文案、构建校验）。
4. **顺手清理**：L 系列按文件顺路修复；先处理 L7（UA 版本）、L28（lint）、L29（仓库卫生）。

---

## 修复记录（2026-08 已实施）

已修复并验证（`flutter analyze` 0 问题、`flutter test` 179/179 通过）：

- **H1**：`ios/Runner/Info.plist` 增加 `NSCameraUsageDescription` 与 `NSPhotoLibraryUsageDescription`。
- **H2**：`session_controller._bootstrap` 包 try/catch，安全存储故障回落 signedOut + 提示。
- **H3**：`auth_screen` 加同步 `_startingOAuth` 重入守卫；`signInWithOAuth` 入口加 `isRefreshing` 纵深防御。
- **M1/M2**：`schedule_controller` 加 `_loadGeneration` 代际守卫，load/delete/persist 全部错误处理。
- **M3/M4**：`rss_controller` 写操作与 reload 错误处理；`bindSubject` 改为先查询再决定 insert/update。
- **M5**：`changeCollection` 章节补完失败返回可见警告文案。
- **M6**：`website_login_screen` 改为先 await 加载 Cookie 再构建 WebView（修复已保存会话不注入）。
- **M7**：`pm_page` 线程加载加 requested-thread 守卫，加载中禁用 composer。
- **M8**：character/person/score-trends/subject-meta 独立请求逐条容错，不再一损俱损。
- **M9**：subject_detail 角色/制作人员/关联/讨论/吐槽/好友收藏分区错误提示 + 重试按钮。
- **M10**：`_CourseTable` 按星期预分组一次，消除数百次 O(n) itemsOn 调用。
- **M11**：bangumi_api/netaba_api 拦截器按状态码/超时优先判定，401/429 文案可达。
- **M12**：`getUserCollections` 带 maxItems 时先排序再截断。
- **M13**：community_service 三个内存缓存写入时清理过期项 + 400 条上限。
- **M14**：`_getJson` 重试统一复用 `_shouldRetry`（含 429）。
- **M15**：RSS HttpDate.parse 支持 +0800 等时区偏移。
- **M16**：移动端内嵌 WebView 加 bgm.tv/bangumi.tv/chii.in 导航白名单，外链转系统浏览器（Windows 插件 1.1.1 无导航拦截 API，暂无法覆盖）。
- **M17**：`tool/build_release.ps1` 构建后校验产物存在且非空。
- **L1**：三处 DropdownButtonFormField 改 `initialValue`，移除 ignore 注释；rss_sheets 默认源改为构建期计算。
- **L2**：条目详情缓存加 10 分钟 TTL + 过期清理。
- **L3**：RSS guid 改用稳定 FNV-1a 摘要替代 hashCode。
- **L4**：RSS 非法 XML 抛中文 FormatException。
- **L5**：Cookie 捕获只剥外层引号；域名归一化精确匹配 .bgm.tv。
- **L7**：新增 `bangumi_user_agent.dart` 统一 UA 版本（v1.5.0），9 处全部收敛。
- **L8**：删除死代码 `_collectionsInFlight`。
- **L11**：社区编辑器在拉取 Turnstile token 前即锁按钮。
- **L14**：profile/subject_detail 头像昵称空串保护。
- **L15**：_ExpandableText 测量用 TextPainter 用后即释放。
- **L17**：搜索回车提交前取消防抖定时器。
- **L18**：subject_detail 错误文案统一剥 Exception 前缀。
- **L19**：user_profile 去掉重复 isFriend 请求。
- **L23**：扫码选图 >1MB 走 `compute` 后台解码。
- **L25**：删除死代码 `friend_collections_page.dart`。
- **L27**：.gitignore 增加 `**/*.keystore`。
- **L13**：theme/background 存储失败 debugPrint 留痕。
- **L12**：oauth 授权对话框 dispose 单飞 + _disposed 标志，修复并发释放竞态。
- **L10**：点格子面板仅在发生改动时刷新收藏（PopScope 携带 changed 结果）。

暂缓（需决策或平台限制）：

- **H4 PKCE**：需确认 Bangumi OAuth 服务端支持 code_challenge 后再迁移；README 已声明现有威胁模型，建议先轮换 secret。
- **M16 Windows**：webview_flutter_windows 1.1.1 未暴露导航拦截 API，升级插件或等待上游。
- **L9**（restartApp exit(0)）、**L6**（正则解析评论区）、**L16**（移动端分享导出）、**L21/L22**（PM/通知分页）、**L28**（启用严格 lint）、**L20/L29**（示例路径与仓库卫生）：涉及平台语义或产品决策，留待后续版本。
