# 工作区冗余清理（2026-10-14）

## 清理结果

共移除 128 个生成目录/文件目标、7,660 个生成文件，逻辑大小为 10,210,155,790 字节，约 9.51 GiB。后续编译和测试会重新生成所需缓存，这个数字不是复核后磁盘剩余空间的净变化。

| 类别 | 内容 |
| --- | --- |
| 旧 Flutter 构建缓存 | 83 个哈希目录，目录内所有文件均超过 7 天；近期构建缓存保留 |
| Android 中间产物 | app/intermediates、generated、kotlin、tmp；APK/AAB 输出保留 |
| 测试与脚本缓存 | Flutter 测试内核、Python 字节码和 pytest 缓存、合成工具链测试临时目录 |
| 临时探测与旧网站输出 | 无项目引用的 .tmp-shaft 编译探测文件、旧 .next 和 .vinext 输出 |
| 旧日志 | 现有清理脚本允许移除且未被文档引用的中间日志 |

另移除 `lib/features/pm/presentation/pm_mailbox_view.dart`。它的公开组件和文件均没有 lib/test/integration_test/tool/packages 的代码引用，现有私信页面已使用 `pm_contacts_view.dart`。原文件包含未提交修改，删除前将完整内容备份到 `.dart_tool/cleanup-review-2026-10-14/retained-worktree/pm_mailbox_view.dart`，校验值与原文件一致。历史架构文档注明该模块已被替代。

## 保留与核对

- 保留未提交的新功能、当前依赖、SDK/模拟器、Python 环境和研究模型。
- 保留正式发布包、调试符号、Shorebird 基线记录、验收报告和截图。
- 保留数据库、WebView 配置、OAuth 和其他本地配置。264 个配置、发布与可运行产物文件的哈希在清理前后一致。
- 除上述明确删除的旧组件、架构说明和本次文档索引外，现有工作区文件按逐文件哈希核对，未覆盖其他改动。
- 删除仅使用 Windows 原生 PowerShell 的 LiteralPath；每个递归目标先验证绝对路径位于工作区内，拒绝目录链接、代码/未忽略文件、运行中的目标和含数据库、密钥、模型或符号的目录。
- 安全规则拒绝清理的候选保留；没有按文件名中的 draft/backup 或文件年龄批量删除源码、数据及验收材料。

本机清单在 `.dart_tool/cleanup-review-2026-10-14/summary.json`、`extra-removal.json` 和 `preservation-check.json`。清理没有提交、发布或修改运行中的账号状态。

## 验证

使用固定工具链执行私信定向回归、清理脚本安全测试、架构检查及 `tool/verify_all.ps1 -Mode Quick -Areas flutter,tools`。实际结果以本轮生成的 verification JSON 为准；未执行的设备、发布和真实账号操作不算通过。
