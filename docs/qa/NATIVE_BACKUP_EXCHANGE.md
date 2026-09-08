# 原生备份互导验证

日期：2026-09-08。此记录覆盖 M6 原生 SQLite、文件对话框、跨平台数据和备份页面；不作为官网登录、消息发送、实际通知或真机性能的替代证据。

## 测试方式

入口为 `tool/qa/native_backup_probe.dart`，普通 `lib/main.dart` 不导入它。探针使用合成账号 `alice / UID 11`、隔离数据库和测试会话；通知由测试替身接管，未访问真实私信或修改真实收藏。

- Windows：Shorebird Flutter 3.44.7 的 debug 构建，数据在 `.dart_tool/m6-native/windows`。
- Android：同版 Shorebird 的 release 探针，运行于专用 Android 35 Google APIs x86_64 模拟器。数据库在应用内部的 `files/native-backup-qa`；供主机取证的 JSON 在应用专用外部目录 `files/MuBangumi-QA`。
- 两端使用真实 SQLite 插件和真实系统文件选择／保存对话框。源码中的 FilePicker 适配与应用相同，没有用路径选择替身代替原生对话框。

Windows debug 探针有仅本机可访问的 QA service extension，可用 `tool/qa/probe_command.py` 请求操作和截图。Windows 文件对话框脚本只接受本项目 debug 探针进程，并核对对话框标题、控件归属及 `.dart_tool/m6-native` 下的 JSON 路径。Android 原生按钮和 DocumentsUI 使用 ADB／UIAutomator 的实际控件位置操作。

## 已验证结果

| 检查 | 证据与结果 |
| --- | --- |
| Windows 本地原生恢复 | 六个数据库、八类数据导出并恢复到空白目标，关闭重开内容一致；`windows-initial-report.json` |
| Windows 进程重启 | 关闭并重新启动探针，核对上次写入的目标数据；探针报告 `process_restart_verified=true` |
| Windows 原生保存 | 使用系统“保存 MuBangumi 备份”对话框保存到测试目录；文件与导出原文逐字节相同；`windows-save-report.json` |
| Android 本地原生恢复 | 使用 Android 内部 SQLite 路径恢复八类数据，核对后重开成功；初次数据恢复耗时记录 1149 ms，仅为此模拟器的单次样本 |
| Windows → Android | 从 DocumentsUI 选择 Windows JSON，实际导入并重开核对；报告 `changed=true`、`cross_file_verified=true`，同步调用数为 0 |
| Android 原生保存 | 使用 DocumentsUI 保存 JSON 到测试 Download 目录，保存文件与 Android 导出原文逐字节相同 |
| Android → Windows | Windows 原生选择 Android 保存文件，导入并重开核对；`windows-android-import-report.json`，记录 `changed=true` |
| Windows → Android → Windows | Android 将导入结果重新导出，Windows 再通过原生对话框读取并导入；八类完整数据与原始 Windows 数据相同；`windows-roundtrip-report.json` |
| 实际备份页面 | 在两端原生宿主中打开应用的 `BackupPage`，截图检查账号、类别和草稿默认不选；Windows 采用深色、Android 采用浅色 |

独立验证命令 `python tool/qa/verify_native_backup_exchange.py` 已通过。它校验每个文件自身的 SHA-256、账号、八类数据、原生保存字节一致性，以及 Windows → Android → Windows 的完整字段相等；同时检查未带入另一账号或缓存中的合成标记。结果在 `.dart_tool/m6-native/exchange-verification.json`。

| 文件对 | SHA-256 |
| --- | --- |
| Windows 原生保存及参考文件 | `ddaf60c65f86363dcbdd79a34b86fc19839aea8d2befe0e326e78fdf09d80020` |
| Android 原生保存及参考文件 | `8c46e0e089efba299cc09fda71c175c2a4af763ee04a8f3eb274208f6476798c` |

Windows 原始数据与完整往返结果的规范化数据摘要均为 `0671c104314b951a6cd46a0cc581206e5adf155f8945d35e56cb7458ce8d0c64`。重新导出的时间不同，因此不能要求两个完整文件的哈希相同。

截图位于 `.dart_tool/m6-native/windows-backup-page.png`、`.dart_tool/m6-native/android/backup-page.png`，原生保存／选择控件树在同目录 XML 文件中。ADB 推入 Downloads 的 JSON 已通过媒体扫描登记；尚未登记时，DocumentsUI 不显示它。

## 仍需复核的问题

- Shorebird 3.44.7 的 Android debug 构建遇到引擎 Maven 元数据版本不一致，未获得可运行的 debug 探针。因此 Android 原生检查改用了同版 release 构建，未替换应用引擎版本来冒充验证。
- Android 35／WHPX 模拟器中的探针出现两次原生崩溃；一次位于 `EmojiCompatInit` 的 ART `nterp_helper` 调用栈。系统预装 Messaging、系统 UIAutomator 和 logd 也各有原生崩溃记录。后续导入后的重启未完成，旧报告不能当作此次重启成功的证据。
- 功能成功的报告来自仍在正常运行时完成的实际文件操作和逐字段核对；上述崩溃意味着此环境的稳定性验收仍不通过，不能据此认定为应用问题或已经解决。
- 同一 AVD 的软件 CPU 模拟尝试未保持运行。正在准备位于 E 盘的另一套系统镜像进行独立复核；C 盘的未完成 SDK 安装残留保留，未执行被自动审批拦截的清理命令。
- 原生截图发现浅色透明 AppBar 令系统状态栏图标变白。应用主题已显式按深浅色设置系统图标样式，并为黑色扫码页保留浅色图标；需用重新构建的包核对最终效果。

## 产物隔离

`dist/MuBangumi-2.2.0-android.apk` 和 Windows ZIP 是正常应用入口的验收包。探针单独保存在 `.dart_tool/m6-native/MuBangumi-native-probe.apk`。构建探针会占用 Flutter 默认构建输出，分发前必须重新构建正常应用或使用已经核对过哈希的正常 `dist` 文件，不能把探针 APK 当作正式包。

最终包已重新构建并包含状态栏修正，附件哈希见 [整体验收记录](OVERALL_ACCEPTANCE.md)。使用同一 Shorebird Flutter 3.44.7 再次运行全部 747 项测试通过，静态检查无问题；原生状态栏效果与稳定性继续复核。整个阶段未上传 GitHub Release 或 Shorebird 发布基线。
