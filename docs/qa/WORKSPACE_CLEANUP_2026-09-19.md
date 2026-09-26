# 工作区整理记录

本次按用途和引用清理本机生成的中间文件，没有按文件名里的 draft / backup 批量删除，也没有删除或覆盖尚未发布的源码改动。

## 已清理

| 类别 | 数量 | 体积 |
| --- | ---: | ---: |
| Windows 打包中转目录 | 23 份 | 975.72 MiB |
| Flutter 测试内核缓存 | 12 个文件 | 879.19 MiB |
| 超过两天且未被 Markdown 文档引用的旧中间日志 | 285 个 | 4.27 MiB |
| 已确认执行完、无当前引用的一次性源码转换脚本 | 8 个 | 0.03 MiB |
| pytest 缓存 | 1 个目录 | 0.02 MiB |

合计移除 318 个清理目标、1,064 个文件，约 1,859.22 MiB（1.82 GiB）。这是文件逻辑大小，不是底层磁盘簇占用的精确测量。清单保存在本机 `.dart_tool/cleanup-20260919-052613-484.json`。

被移除的一次性脚本为 `cache_typed_snapshots.py`、`normalize_room_store.py`、`scope_community_cache.py`、`scope_services.py`、`coverage_pipeline.py`、`migrate_routes.py`、`wrap_route_tests.dart`、`room_web_comments.py`，均位于 `.dart_tool/`，对应修改已存在于现有源码。这次处理后，日常清理脚本不再自动删除源码转换脚本。

## 保留与验证

- 清理前后 468 个 lib / test / Android / assets / pubspec 源文件哈希一致，包含未发布改动。
- 2.3.1 正式发布附件的 SHA256 与既有校验清单一致；其他 dist 历史包与宣传片保持原样。
- 保留 release-symbols、`.dart_tool/flutter-symbols`、最新 Shorebird 日志、文档引用的验收记录与截图。
- 保留 SDK、模拟器、Python 环境和语义模型缓存。这些开发依赖占用较大，但不属于可随意丢弃的草稿。
- 保留项目配置、密钥、数据库、WebView 数据、冻结的原生 Android 原型及推荐研究工具。
- 清理脚本 8 项检查通过：预览不删除、目标缓存删除、已跟踪文件/用户数据库/正式产物保护、禁止沿目录链接越界。
- Windows 包安全 13 项检查通过，PowerShell 语法与仓库隐私检查通过。

新增 [文档索引](../README.md)、[工具索引](../../tool/README.md)和默认仅预览的清理脚本。Windows 打包脚本增加成功后清理自身中转目录的逻辑，并提供 `-KeepStaging`；生成 ZIP 失败时保留中转文件用于诊断。

额外的真实打包验证命令被自动审批拦截，返回信息仅为 `blocked by policy`，因此未执行该次打包验证。工作区实际清理由范围受限、经单独检查的脚本完成；未尝试重新执行被拦截的命令。
