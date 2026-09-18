# 会话职责拆分：第一阶段

日期：2026-09-14。基于 `v2.2.0+27`，分支 `refactor/session-responsibilities`。

本文记录第一阶段。随后完成的收藏加载与编辑拆分见 [第二阶段记录](COLLECTION_REFACTOR.md)。

## 本轮范围

原 `SessionController` 同时承担凭据存取与刷新、登录页面状态、收藏合并、章节编辑、队列上传和定时重试。本轮提取可以独立验证的职责，保留 `sessionProvider`、`SessionController` 构造参数及页面调用接口。

| 入口 | 职责 |
| --- | --- |
| `lib/state/session_controller.dart` | 登录、退出、账号批次、首页准备和收藏编辑的编排；将模块结果转换成页面状态 |
| `lib/state/session_state.dart` | 页面可观察的会话状态；原入口继续导出，兼容现有调用方 |
| `lib/state/app_providers.dart` | API、OAuth、凭据存储和快照缓存的共享 Provider |
| `lib/features/auth/application/session_credentials.dart` | 凭据读取、内存缓存、串行写入、刷新请求合并、过期判断；不决定展示哪个账号 |
| `lib/features/sync/application/pending_sync_controller.dart` | 单队列上传、请求账号保护、队列计数、手动重试与退避定时器；不直接修改全局状态 |
| `lib/features/sync/domain/pending_mutation.dart` | 待同步操作及修订号模型，不依赖 SQLite；原存储入口继续导出 |
| `lib/features/collection/domain/collection_reconciler.dart` | 收藏、章节的纯数据合并规则，不访问网络或数据库 |
| `lib/core/storage/bangumi_sync_store.dart` | SQLite 队列持久化与修订号条件更新，存储格式保持不变 |

新模块不导入 `state/`、`screens/` 或 `widgets/`。会话控制器通过构造注入提供账号读取与状态回调；数据模型不反向依赖存储实现。现有基础设施在迁移期间可以引用纯业务模型。

## 必须保持的行为

- 只有经过账号验证的凭据才可绑定身份并用于离线恢复；没有凭据时仍显示登录页。
- 账号批次由会话控制器统一推进。读取、刷新、同步的迟到结果不能改变后续登录，即使用户名相同。
- 退出清理与凭据写入共享串行屏障：已开始的写入先结束，旧批次排队的写入被跳过，然后清理。
- 并发刷新合并为一个请求；网络暂时失败保留可用凭据，明确失效才清理登录。
- 同步计数回调携带账号批次；旧上传结束后重新读取当前账号待处理数量，再继续新账号队列。
- 退出取消重试定时器，但保留正在执行的上传屏障，避免新旧账号上传并行；销毁模块后不再重试或发布进度。
- 收藏修改仍先落盘再反馈成功。旧请求不能覆盖更新的本地修订，章节完成与后续单集修改保持队列顺序。
- 队列、Token、快照的存储格式及账号归属规则不变；无需数据库迁移。

## 验证

重构前相关测试 73 项通过。新增独立测试覆盖：

- `session_credentials_test.dart`：刷新合并、迟到刷新成功/失败、退出与写入排序、写失败后清理、迟到启动读取。
- `pending_sync_controller_test.dart`：同名账号重新登录后的旧计数、退避与销毁、跨账号队列串行接续。
- `collection_reconciler_test.dart`：仅改状态时保留短评与隐私、旧请求与本地修订合并、章节完成后单集修改及特别篇保护。

最终检查：

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub --reporter expanded`：912 项全部通过，含新增 12 项测试。
- `git diff --check`：通过。
- 原会话控制器从 2,136 行缩减至 1,665 行；提取出的凭据、同步和合并模块均可单独构造或调用。

本轮验证为本地自动化测试，没有执行真实账号的 OAuth 授权或真机回归，也未构建新的发布包。

## 后续边界

本阶段没有把整个应用改成新的架构。后续已完成[收藏加载与编辑拆分](COLLECTION_REFACTOR.md)、[详情展示拆分](SUBJECT_DETAIL_REFACTOR.md)、[新番表拆分](SCHEDULE_REFACTOR.md)及[短信与详情请求收尾](PM_AND_SUBJECT_REQUESTS_REFACTOR.md)。`SessionController` 继续作为兼容入口负责账号状态和模块协调。
