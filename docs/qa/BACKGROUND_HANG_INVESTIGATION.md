# 背景调整后 Windows 无响应：崩溃定位与修复验证

2026-09-12。用户确认 build 18 优化之后仍出现整个窗口长时间无响应。之前 835 项测试和全局刷新次数的改善不能证明该挂起问题已解决。

## 第一阶段：仅测拖动未能复现

新增 `tool/background_drag_benchmark.dart`，通过 Windows 原生 Flutter Profile 构建，在实际设置面板上派发连续指针事件。每个滑杆 180 次移动，松手后等待 2 秒。采集 Flutter build/raster 时长、Dart 定时器间隔和原生存储写入耗时，输出 JSON。

已完成四轮：生成的 2560×1440 图片及内存存储；生成图片及真实 Windows 存储；当前壁纸和真实系统偏好及存储；完整 MuBangumiApp 已登录状态、当前壁纸、真实系统偏好及存储。四轮均未复现长时间挂起，三个滑杆的末值确实变化，三次提交均完成。最后一轮原生写入分别为 18.235 / 15.151 / 12.675 毫秒。当前壁纸仅为 640×640、56,375 字节，未见图片尺寸过大的证据。

所有背景调整都写入内存或唯一 `qa_background_probe_*` 测试键，结束时删除测试键；未覆盖用户的背景参数。读取实际壁纸时只输出尺寸和字节数，不记录路径、图片内容或账号。完整应用按正常启动行为恢复会话；基准入口不初始化 main.dart 中的通知服务。

测量限制：指针由 Flutter 手势入口派发，未覆盖真实鼠标经过 Windows 消息处理的完整链路；Profile 不是 Release；没有捕获用户遇到的挂起现场。定时器约 17–31 ms 的间隔受系统调度影响，不能当作显示帧率。帧回调批量返回，各阶段边界附近的帧归属可能偏移。

输出位于 `.dart_tool/background-benchmark/`：`before.json`、`native-storage.json`、`actual-wallpaper.json`、`actual-app.json`。默认运行生成图与内存存储；可通过 `NATIVE_BACKGROUND_STORAGE`、`REAL_BACKGROUND_IMAGE`、`NATIVE_SYSTEM_APPEARANCE`、`REAL_APP` 四个布尔 Dart define 选择上述对照。`BENCHMARK_RESULT` 指定本地 JSON 输出路径。

## 第二阶段：build 19 现场捕获

build 19 使用 `BACKGROUND_DIAGNOSTICS=true`，设置标题标为“背景与毛玻璃 · 诊断版”。仅诊断构建启用 `BackgroundDiagnostics`，在 EXE 同目录写入 `background-diagnostic.jsonl`，包括每秒心跳、构建/渲染最大时长、调整次数、拖动开始、参数应用、原生保存开始/结束、系统偏好读取开始/结束。字段不包含令牌、账号、文件路径或图片。

外部只读观察脚本另外记录窗口是否响应、CPU、内存；发现不响应时记录线程等待类型。build 19 发布预览时仍处于“等待捕获实际挂起”，不是“已修复”。

诊断调用接入后，背景与系统效果专项 29 项回归测试通过。没有以增加诊断记录为由修改原有参数、降低画质或迁移用户存储。

静态检查无问题，Windows Release `2.2.0+19` 构建和 ZIP 运行文件检查通过，解压后的 EXE/app.so 摘要与构建输出一致。诊断预览已启动，启动后的心跳、帧耗时及外部窗口响应日志已实际生成；窗口当前响应正常。外部观察脚本在窗口关闭或约一小时后退出。

本地诊断包：`dist/background-build19/MuBangumi-2.2.0-windows-x64.zip`。SHA-256：`5c5e35ac336b6301be3d750e8b29eb98ac2e9b9c1a551ef3e2acb9a7ffea6d55`。此版本用于现场诊断，未发布到 GitHub。

## 第三阶段：已复现的原生崩溃

用户补充操作顺序：拖完参数，再点击其他控件。17:18 的现场日志显示保存只用了 7 ms，随后 Windows Error Reporting 报告 `flutter_windows.dll` 访问异常 `0xc0000005`（以及派生的 `0xc000041d`），故障 RVA 为 `0xf5d3`。窗口的长时间无响应实际伴随原生崩溃报告流程，并非仍在等待保存。build 17、18、19 的本地转储均为相同位置。

使用与 Flutter 3.44.0 引擎 `4c525dac5ebe5971c5708ef73558ed8edcf4a362` 匹配的官方 PDB 定位：`FlutterPlatformNodeDelegateWindows::HitTestSync` 查询了无效节点，读取地址 8；调用链包含 `AXPlatformNodeWin::accHitTest`、Windows MSAA/UIAutomation。转储仅在本地分析，不随源码、安装包或 GitHub 上传。

新增只读 `tool/probe_windows_accessibility.ps1`，在拖动基准运行时对 Flutter 子窗口执行 MSAA `accHitTest`。原版本可复现相同 RVA 的崩溃；原生 stderr 先报告 `Failed to update ui::AXTree` / `will not be in the tree and is not the new root`，随后访问已损坏的树。

过滤后的语义快照将出错 ID 对应到三个滑杆附带的全窗口空浮层节点。Flutter 3.44 的 Material Slider 即使 `showValueIndicator: never` 仍创建并显示 OverlayPortal；仅在 Slider 外包 ExcludeSemantics 无法覆盖挂到 Navigator overlay 的内容。只固定滑杆语义矩形或排除预览图，都未消除 AXTree 更新错误。

## 修复方式

Windows 的 `AppSlider` 用尺寸随滑杆的局部 Overlay 容纳指示浮层，并将整棵内部树排除出语义树；外部提供一个固定范围的可调整滑杆节点。保留系统无障碍标签、当前/增减值、焦点、键盘方向键和开始/完成回调。没有关闭整个应用的无障碍功能，没有修改 Flutter SDK 或引擎二进制。

数值格式化改为由每种参数显式提供，避免辅助技术播报增减值时始终返回当前值；重复的视觉标签及纯装饰壁纸/预览不再单独播报。继续保留“拖动时局部预览，松手后应用并保存”。

首次局部浮层 Profile 验证完成三个滑杆各 180 次移动、3,189 次原生命中查询，原生 stderr 为 0 字节，基准正常产出结果。查询脚本在进程退出时捕获一次 COM 断开；后续脚本将进程退出竞态与运行中查询错误分别计数。专项回归实际为 30 项通过。

最终验证另用 Release 构建，增加每次拖动后点击高级调整折叠/展开，以及关闭设置后重新打开。结果与包信息见下方最终验收记录。

## 最终自动验证（2026-09-12）

- Release 基准：三个滑杆各 180 次移动，拖后折叠/展开均完成，重开设置后有 3 个滑杆。进程退出码 0。
- 同期原生 MSAA 查询 4,272 次，运行中错误 0，退出竞态 0；原生 stderr 0 字节，对应进程没有新增 Application Error 1000 事件。
- `flutter test --no-pub`：838 项通过，包含滑杆语义节点边界、匿名全窗口节点泄漏、辅助技术调整及键盘回归。
- `flutter analyze --no-pub lib test tool/background_drag_benchmark.dart`：无问题。第一次不限定路径的检查未结束，停止该次分析进程后改为明确检查应用、全部测试和新增基准入口。
- 自动基准之外，用户已确认 build 20 实际窗口的“拖完再点击”操作没有问题，实际鼠标验收通过。

本地原始结果：`.dart_tool/background-benchmark/final-release.json`、`.dart_tool/background-accessibility-release.log`、`.dart_tool/background-release-exit.json`、`.dart_tool/background-release-error.log`。

复测时先以 `-t tool/background_drag_benchmark.dart` 构建 Windows Release，再启动程序并同步运行 `tool/probe_windows_accessibility.ps1 -PreviewProcessId <PID> -Seconds 45`。只看 JSON/退出码不够，必须同时检查 stderr 没有 AXTree 更新失败及 Windows 事件没有该进程的原生崩溃。完成后必须重新以 `-t lib/main.dart` 构建应用，不能打包基准入口。

## build 20 本地交付

已重新从 `lib/main.dart` 构建 `2.2.0+20`，启用 `BACKGROUND_DIAGNOSTICS=true`、`BACKGROUND_DIAGNOSTIC_BUILD=20`，设置页标题明确标识诊断版 20。ZIP 仅含运行文件的检查通过；解压 EXE 和 app.so 与构建输出的 SHA-256 一致。

包：`dist/background-build20/MuBangumi-2.2.0-windows-x64.zip`，19,367,776 字节。SHA-256：`0e01cecbcd871e49aadab534e1468038a0962634b1dcf8204e59ace2e0423714`。未发布到 GitHub。

解压后的正式入口预览已启动，12 秒额外 MSAA 启动检查完成 2,048 次查询、0 错误，窗口响应正常，诊断日志确认 build 20 且心跳持续。此项只覆盖启动后的原生查询；拖动后的原生复现覆盖来自前述 Release 基准。

## 用户验收

2026-09-12，用户在收到 build 20 的“拖动参数后再点击其他控件”验收说明后反馈“没问题”。本次拖动后窗口卡死问题验收通过。已结束临时外部窗口观察任务，保留本地诊断证据。当前 build 20 仍是启用日志的诊断构建，普通构建默认关闭诊断；本次确认不代表已发布 GitHub 正式版本。
