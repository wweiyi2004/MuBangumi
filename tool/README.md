# 开发与维护工具

| 位置 | 用途 |
| --- | --- |
| `toolchain.json`、`toolchain.ps1`、`setup_workspace.ps1` | 固定工具版本、选择本地 SDK 和安装带哈希的依赖 |
| `verify_all.ps1` | 快速/完整验证与 JSON 结果，失败返回非零退出码，标记未运行平台 |
| `lock_python.ps1` | 从各 requirements.in 生成完整哈希锁文件；`-Upgrade` 用于受控升级 |
| `release_provenance.py` | 源码指纹、工具版本、验证/人工验收校验、产物哈希与补丁回执 |
| `build_release.ps1` | Flutter / Shorebird 构建与产物检查 |
| `package_windows_release.ps1` | 只打包允许分发的 Windows 运行文件；成功后自动移除自己的中转目录，`-KeepStaging` 可保留诊断副本 |
| `verify_windows_package.ps1`、`windows_package_safety.ps1` | Windows 包路径、运行数据与隐私检查 |
| `verify_repository_privacy.ps1`、`verify_architecture.py` | 仓库敏感文件与架构边界检查 |
| `qa/` | 可重复执行的服务、浏览器、原生备份等验证工具 |
| `tests/` | 构建、打包和清理脚本的回归检查 |
| `maintenance/` | 定向维护操作；阅读具体脚本说明后运行 |
| `recommend_dataset/`、`semantic_retrieval/` | 推荐数据与语义检索原型，不属于可丢弃的构建草稿 |

完整维护入口见 [CONTRIBUTING.md](../CONTRIBUTING.md)。`build_release.ps1 -AllowDirty` 只允许本地普通构建；Shorebird 上传必须使用干净源码，并提供最近 7 天内、匹配源码指纹的完整验证与人工验收记录。`-DryRun` 可以验证未提交改动，但不构成正式发布验收。

Windows 本地可运行 `./tool/verify_all.ps1 -Mode Full -WindowsSmoke`，追加独立入口的安全存储、SQLite 和 WebView 冒烟。未运行的移动设备/iOS 构建及人工验收仍单独列出，不因本地冒烟通过而消失。

普通 Flutter 通用 APK 使用 `./tool/build_release.ps1 -Target apk -UniversalApk -VerificationReport <results.json>`。该选项保留 pubspec 的原始 versionCode，避免 ABI 分包为构建号增加偏移；不改变 Shorebird 基线。省略该选项仍保留原来的分架构构建行为。

## 清理本地中间产物

在仓库根目录使用 PowerShell：

```powershell
# 默认只预览，清单写入 .dart_tool/cleanup-时间.json
./tool/maintenance/clean_workspace.ps1 -IncludeTestCache

# 核对后执行；省略 IncludeTestCache 会保留测试编译缓存
./tool/maintenance/clean_workspace.ps1 -Apply -IncludeTestCache
```

日常清理范围限于：`windows-package-<GUID>` 打包中转副本、pytest 缓存、可选的 Flutter 测试内核缓存、超过两天且未被 Markdown 文档引用的中间日志。日志中的 release / shorebird / semantic 前缀保留。一次性代码修改脚本需单独核对是否已完成、是否还有引用，不由日常清理自动删除。

脚本拒绝清理越界路径、链接、Git 跟踪文件、含隐私数据的打包副本或正在运行的中转程序。SDK、模拟器、虚拟环境、模型缓存、安装包、视频、调试符号、数据库和配置文件均不在清理范围内。清理测试内核后，下次测试会重新编译，首次启动可能更慢。

不要按 `draft`、`backup` 等文件名全局删除：`lib/` 和 `test/` 下的草稿、备份文件通常是应用功能与测试源码。
