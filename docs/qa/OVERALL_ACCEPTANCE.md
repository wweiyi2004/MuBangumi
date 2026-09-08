# 长期体验改进整体验收

记录日期：2026-09-08。状态：七项功能的实现及自动化验证完成，原生组合验收继续进行。GitHub 最新发布仍为 `v2.1.1`，以下 `2.2.0+12` 是本地验收包，未上传 Release 或 Shorebird 基线。

## 功能证据

| 范围 | 本地实现 | 自动化证据 | 原生待验收 |
| --- | --- | --- | --- |
| 私信草稿 | `e748904` | [M1 记录](M1_PRIVATE_MESSAGE_DRAFTS.md)，含按账号／会话恢复、失败及迟到保存 | 原生输入法、系统结束进程、官网会话组合 |
| 观看进度撤销 | `53fed21` | [M2 记录](M2_PROGRESS_AND_PINS.md)，含离线队列与后续修改保护 | 设备触控、后台恢复与服务组合 |
| 首页置顶 | `53fed21` | 同 M2，含排序、重启和账号隔离 | 原生运行重启与操作耗时 |
| 手机新番表列表 | `4bdc2bb` | [M3 记录](M3_SCHEDULE_LISTS.md)，含三视图、跨日和时区 | 实际通知、恢复前台及日期边界 |
| 不感兴趣反馈 | `59b31b1` | [M4 记录](M4_RECOMMENDATION_FEEDBACK.md)，含恢复、账号与候选过滤 | 原生筛选、滚动与持久化 |
| 收藏批量整理 | `d9c9e82` | [M5 记录](M5_LIBRARY_BATCH.md)，含真实 SQLite 的 1／50 项与重启续传 | 原生返回／停止、多选与耗时 |
| 本地备份与导入 | `7aae41f`、`9e3d1f1`、`f1346dd` | [M6 记录](M6_LOCAL_BACKUP.md)，含八类恢复、真实进程退出及账号保护 | 原生文件选择／分享、Android／Windows 互导 |

最新完整功能检查为 747 项 Flutter 测试通过，`flutter analyze --no-pub lib test tool/qa/backup_crash_probe.dart` 无问题。M6 额外有 72 张真实字体渲染截图。上述属于自动化与渲染测试证据，不能替代真机验收。

## 本地安装产物

使用已配置的 Shorebird Flutter `3.44.7`，分别执行：

```powershell
.\tool\build_release.ps1 -Target windows -Shorebird -DryRun
.\tool\build_release.ps1 -Target apk -Shorebird -DryRun
.\tool\package_windows_release.ps1 -Version 2.2.0
```

已核对本机 Shorebird CLI 的实现：dry-run 在构建和版本校验后退出，位于创建发布记录和上传产物之前。因此这两次成功构建不代表已发布。

| 产物 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `dist/MuBangumi-2.2.0-android.apk` | 102839881 | `6e009d6da5b476fb697e3122e318db4342ebe0be89d13fe4fe65dc06ec278efa` |
| `dist/MuBangumi-2.2.0-windows-x64.zip` | 19472514 | `146acc2f9d1f1a1a831234262bce5f3856e6f25d899897833862d1793fb7fefa` |

独立校验文件：`dist/SHA256SUMS-2.2.0-QA.txt`。以上为包含状态栏修正后重新构建的产物；最新日志为 `.dart_tool/m6-final-build-android.log`、`.dart_tool/m6-final-build-windows.log`，检查 JSON 为 `.dart_tool/m6-artifacts-final.json`。额外以探针专用字符串校验 APK／Windows AOT 内容，确认正常产物没有误用探针入口。

Android 包名 `com.wweiyi.mubangumi`，`versionName=2.2.0`、`versionCode=12`、`minSdk=24`、`targetSdk=36`。APK v2 签名验证通过，证书 SHA-256 为 `e08e8ae54c8ac1718bbbf2cd82e18fe7ab6362e42a3a0739941a5eda77222863`，与已发布 2.1.1 APK 一致。

Windows 可执行文件 ProductVersion 为 `2.2.0+12`。原有 ZIP 未附带可执行文件依赖的 Visual C++ 运行库；打包脚本现从已安装 Visual Studio 的 x64 CRT Redistributable 目录补入运行库，支持通过 `-VisualCppRuntimePath` 指定目录，并检查三个必要 DLL。处理方式依据 [Flutter Windows ZIP 分发说明](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows)。本次使用 MSVC Redist `14.44.35112`；运行库就近加载，无需修改系统目录。

最终 ZIP 包含 34 个文件，APK 包含 376 个条目；CRC 检查通过，没有附带 SQLite 数据文件、Cookie 文件或 `oauth.local.json`。Windows 保留相对 DLL 名称的 SQLite native-assets 清单、Flutter AOT／ICU、插件与资源文件。候选源文件扫描未发现本地 OAuth Secret。未将编译所需的应用 OAuth 配置误作用户登录凭据。

## Android 初步原生检查

已建立专用、无真实账号的 Android 35 Google APIs x86_64 模拟器，设备 ID `emulator-5556`，Pixel 5 配置，1080×2340，2 核／2048 MB、WHPX 加速和 SwiftShader。AVD 文件位于 `.dart_tool/m6-avd`，未使用其他设备的数据。

- `adb install -r` 成功，系统包信息确认版本 2.2.0／12。
- `am start -W` 首次启动成功：`LaunchState=COLD`、`TotalTime=1974 ms`、`WaitTime=1992 ms`。
- 已检查实际设备截图 `.dart_tool/m6-android-start.png`，登录入口正常显示。启动后的 AndroidRuntime／Flutter 错误日志没有错误输出。

这是一次模拟器 Activity 冷启动测量，不能代表真机性能、完成登录后的首页加载或分位数结果。尚未用真实账号登录，也未发送真实消息或修改真实收藏。

## 剩余验收

原生备份已完成双向文件选择、保存和完整往返数据验证，详见 [原生互导记录](NATIVE_BACKUP_EXCHANGE.md)。该记录同时保留 Android 35 模拟器的 ART 崩溃及未完成的重启复核，不能将功能验证成功扩大为整体稳定性通过。

- 在隔离的原生测试环境验证八类数据的 Windows → Android → Windows 互导、文件对话框和分享，并保留可复查的输入、结果摘要和截图。
- 安装产物的 Windows 启动与插件组合；Android 包的升级安装、后台／进程重启及功能操作。
- 各阶段的原生触控、输入法、通知和官网会话组合。消息发送相关验证只能使用明确授权的测试场景。
- 真机冷启动、恢复前台、滚动和关键操作耗时；当前尚未接入 Android 手机，已向用户询问连接安排。
- 发布前核对版本、签名、Shorebird 基线、产物与附件哈希；本轮未发布。

历史 v2.1.0 Windows 附件含本地数据库目录的问题仍为独立维护项，尚未清理远端附件。
