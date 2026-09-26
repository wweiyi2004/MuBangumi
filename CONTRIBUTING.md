# 开发与维护

正式客户端为根目录 Flutter 项目；`native-android` 是冻结原型。网站和 Python 研究工具分别维护，不能把研究评估结果当成客户端功能验收。

工具版本以 `tool/toolchain.json` 为准：Flutter 3.44.7、Node 22.23.2；Python 各工具使用独立虚拟环境。`.fvmrc` 和 `website/.node-version` 由一致性检查保护。本地工具路径保存在被忽略的 `.dart_tool/toolchain.local.json`，不更改系统默认 SDK。

普通构建使用官方 Flutter，工具同时检查 framework 和 engine 提交。同样标为 3.44.7 的 Shorebird 缓存 fork 不一定兼容普通 Android 构建；Shorebird 自己选择的发布/补丁引擎由其 CLI 与服务端基线管理。

```powershell
# 也可使用 FVM 安装 .fvmrc 指定的 Flutter；显式路径用于复用已有安装。
./tool/setup_workspace.ps1 -FlutterRoot <Flutter根目录> -NodePath <node可执行文件> -Flutter -Website -Python -Browsers
./tool/verify_all.ps1
./tool/verify_all.ps1 -Mode Full
# Windows 本地原生插件与 WebView 冒烟（独立测试入口、合成数据）。
./tool/verify_all.ps1 -Mode Full -WindowsSmoke
```

快速验证包含静态分析、全部单元测试、网站检查和脚本防护；完整验证增加本平台构建、Android 构建、服务端 bundle 和网站浏览器交互。iOS 由 macOS CI 构建，设备测试需 `-DeviceId`。每次生成 `.dart_tool/verification/<run>/results.json`；任何必需步骤失败都返回非零退出码，未运行项目单列。

`-WindowsSmoke` 仅用于 Windows 上的 Full Flutter 验证，运行安全存储、SQLite 与本地 WebView 测试；它不代表 Android/iOS 或真实账号验收。无论是否传入设备 ID，报告均保留真实账号、文件互导、提醒与更新安装的人工验收边界。CI 已配置不代表当前源码已在云端执行。

Python 输入依赖位于 `requirements.in`，完整带哈希锁文件为对应 `requirements.txt`。升级时运行 `tool/lock_python.ps1 -Upgrade`，重新安装并测试三个环境，再一起提交输入与锁文件。普通安装使用 `--require-hashes`；网站使用 `npm ci`。浏览器测试首次运行前通过项目 Node 执行 `npx playwright install chromium`；统一工具将浏览器缓存放到 `.dart_tool/playwright`。

每个改动保持单一行为目标，并给出正常、失败与恢复的验证证据。认证写操作通过 `CommunityWriteClient` 的账号保护执行；私信等追加写入不能在结果未知时自动重发。新增持久状态需要账号归属、迁移与中断恢复用例。保留 `tool/verify_architecture.py` 的层级与依赖约束。

发布从已提交、内容可追溯的源码进行。`build_release.ps1` 为普通包和 Shorebird 输出 provenance.json；真实上传要求匹配源码的完整验证与人工设备验收。`-AllowDirty` 仅用于本地普通构建，不能绕过 Shorebird 上传的干净源码要求。详见 [设备验收](docs/qa/ANDROID_RELEASE_CHECKLIST.md)。

不要提交配置凭据、运行数据库、浏览器用户目录、模型/用户数据集、构建目录或调试符号。不要把 UI 试用或构建成功写成真实账号验证通过。
