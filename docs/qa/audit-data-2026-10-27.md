# 数据、会话与异步审计（2026-10-27）

本分支工作保留了开始审计时已有的工作区改动，没有提交、重置或清理本地数据。

## 已修复

- `lib/state/pm_draft_controller.dart`：同一编辑版本重复调用 `enqueue` 时，原实现先捕获相同正文，再依次执行两个本地事务。第一个事务更新 `_revision` 后，第二个事务使用这个新版本再次入队，绕过存储层按草稿版本去重，产生两条相同的私信发送任务。现按编辑版本共享尚未完成的入队 Future，并在通知监听器前登记该任务。新输入仍有独立编辑版本，不阻塞下一条消息。
- `test/pm_send_queue_test.dart`：增加延迟本地提交期间重复入队的回归，验证返回相同命令 ID，队列只有一条正文，输入正常清空。

## 检查范围与结果

人工阅读了 `AsyncCache`、API subject 缓存、`CommunityWriteClient`、网站会话控制器、token 存储、snapshot/community 缓存、SQLite 连接和串行任务队列，以及私信草稿、发送队列、邮箱、联系人、通知、RSS、用户备注、好友分组、推荐反馈和首页置顶控制器的相关异步路径。未修改 P1 写入、网站 Cookie 或凭据逻辑；没有新增核心层对屏幕层的依赖。

验证均使用 `tool/toolchain.ps1` 解析的项目锁定 Flutter SDK，以及合成数据：

```powershell
. ./tool/toolchain.ps1
Invoke-MuFlutter -Arguments @('analyze','lib/state/pm_draft_controller.dart')
Invoke-MuFlutter -Arguments @('test','test/pm_send_queue_test.dart','--reporter','expanded')
Invoke-MuFlutter -Arguments @('test','test/pm_draft_controller_test.dart','test/pm_draft_store_test.dart','test/pm_draft_flow_test.dart','test/pm_mailbox_controller_test.dart','test/pm_contacts_test.dart','test/async_cache_test.dart','test/community_account_retry_test.dart','test/community_cache_scope_test.dart','test/community_session_audit_test.dart','test/concurrent_state_recovery_test.dart','--reporter','expanded')
```

- 定向 analyze：无问题。
- 发送队列：11 条通过，包括重复提交、写入失败保留输入、提交期间新输入、预检切账号以及 uncertain POST 不重试。
- 其他上述回归：111 条通过。
- `dart format lib/state/pm_draft_controller.dart`：无格式改动。

全套 `tool/verify_all.ps1` 由主审计统一执行。本分报告不代表设备、云端或已认证在线消息发送验收；未执行真实账号写入测试。

## 依据

[Dart 官方并发文档](https://dart.dev/language/concurrency)说明单 isolate 的事件循环仍可能出现异步竞争；本修复直接合并同一编辑版本的进行中操作，保留现有存储事务与发送结果状态机。
