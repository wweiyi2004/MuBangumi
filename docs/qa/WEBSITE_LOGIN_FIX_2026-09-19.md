# Android 网页补充验证修复

用户反馈：ARM64 安装包从消息进入网页登录后重复回到未登录页面，手动保存无效；提示出现巨大红字和黄色下划线。外部浏览器可登录官网，但没有返回应用。

## 已确认的代码缺陷

1. 锁定使用的 `webview_flutter_android 4.13.0` 在 `getCookies` 中按全部 `=` 分割并只保留最后一段，破坏带等号的 Cookie；`setCookie` 对 Cookie 值再次 `Uri.encodeComponent`，会把已有的 `%` 转义成 `%25`。已改为受限的 Android MethodChannel 调用 `CookieManager`，仅操作 `https://bgm.tv`，按第一个等号解析，原样写回值并保留域、路径等属性。没有修改全局 pub-cache 或升级插件集合。
2. 过期/账号不一致时虽然清理了 WebView，随后登录页面却重新注入磁盘旧快照。新登录会显式跳过该快照；不删除应用 OAuth 登录，也不读取或保存用户输入的密码。
3. 捕获只依赖页面加载完成，且跳过 `/login`。AJAX 登录可能不触发导航。验证页现在在前台定时检查 Cookie，仅在内容变化时自动核验；离开页面取消检查，后台暂停，手动核验仍可重试。
4. 登录页根部使用 ColoredBox，提示没有 Material 默认文字样式。改为 Scaffold 并明确正文样式，也使手动失败的 SnackBar 显示在当前页面。
5. 普通官网外链没有应用登录回调，不会共享系统浏览器的 Cookie。验证页面去掉外部浏览器入口；普通社区浏览页仍可外部打开。不能据此归因于鸿蒙，亦不声称增加了官网没有提供的回调。
6. 账号核验优先读取官网账号导航，在已识别当前账号时不因页面附带登录表单误判过期；账号不匹配、未登录、挑战验证仍正常拒绝。

Android 原始 Cookie API 依据 [CookieManager 官方文档](https://developer.android.com/reference/android/webkit/CookieManager)。普通官网入口见 [Bangumi 登录页](https://bgm.tv/login)。验证使用合成 Cookie 与模拟账号，不记录用户凭据。

## 验证与范围

- Cookie 编码、等号保留、注入域限制与字段校验测试通过。
- 手机窄屏错误提示、旧快照跳过、无导航 AJAX 登录自动捕获、相同 Cookie 不重复保存测试通过。
- 登录、会话、账号访问、私信与社区相关 55 项测试通过。
- Android 原生代码需要重新安装整包；旧安装包不能仅靠 Dart 热更新获得本次修复。
- 未连接用户的鸿蒙手机，尚未在该设备以真实账号完成端到端验证；修复包需要用户实测登录、自动返回与重启后的会话恢复。

静态检查无问题；Android 三种 ABI 与 Windows Release 本地构建通过。ARM64 APK 的 DEX 已核对包含新增原生 Cookie 桥接方法。

独立修复包：`dist/website-login-fix-20260919/MuBangumi-login-fix-android-arm64-v8a.apk`，同目录 `verification.json` 保存 SHA256 与验证范围。仍为 `2.3.0+28` 本地测试构建，未替换已发布 Release。Windows 更新后的本地程序已重新打开。

手机复测：覆盖安装修复 APK → 消息 → 登录后继续 → 在应用内网页登录与当前应用相同的账号。登录成功后应自动核验并返回；再退出并重新打开应用，检查消息会话能否正常恢复。
