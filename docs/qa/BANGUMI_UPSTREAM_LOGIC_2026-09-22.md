# Bangumi 官方 P1 判断逻辑核查

核查时间：2026-09-22。范围是官方 `bangumi/server-private` 中与小组、发帖、回复和可见性有关的实现，不是对全部官方 API 的无遗漏审计。

## 版本证据

- 本次只读 GET [线上 OpenAPI](https://next.bgm.tv/p1/openapi.json) 返回 HTTP 200，`info.version` 为 `2026-09-19-e170542`。
- 该版本对应提交：`e170542e22604b9af742b9bb14fb12d74e4b235e`。
- 同时核对当时 master：`e5340036c228e887185438feb579d8384dbf3954`，下述逻辑在两者中相同。
- 版本号用于关联公开源码，不能单独证明线上运行环境和该提交完全一致。没有发送真实发帖/回复请求，也没有访问真实受限帖子。

## 1. 已确认：小组成员参数顺序传反

[`lib/group/utils.ts:26`](https://github.com/bangumi/server-private/blob/e170542e22604b9af742b9bb14fb12d74e4b235e/lib/group/utils.ts#L26) 定义参数顺序为 `isMemberInGroup(userID, groupID)`；其内部查询明确把第一个参数作为 uid，第二个作为 gid。

但 [`group.ts:476`](https://github.com/bangumi/server-private/blob/e170542e22604b9af742b9bb14fb12d74e4b235e/routes/private/routes/group.ts#L476) 的创建话题和 [`group.ts:820`](https://github.com/bangumi/server-private/blob/e170542e22604b9af742b9bb14fb12d74e4b235e/routes/private/routes/group.ts#L820) 的回复校验都传入了 `isMemberInGroup(group.id, auth.userID)`。

受影响的是非公开小组的这两个写入口。即使用户已加入小组，反向查询仍可能找不到成员记录。小组详情读取在第 186 行使用正确顺序，因此可以出现“界面显示已加入，发帖/回复却被拒绝”的矛盾。

上游所需修正：将这两处调用改为用户 ID 在前、小组 ID 在后，并补充用户 ID 与小组 ID 不相等时的成员/非成员集成测试。客户端不能通过把业务数据中的 ID 交换来修复服务端内部参数错误。

本地复现使用固定提交的原函数，TypeScript 转译后注入虚构数据库，仅含 `uid=101, gid=202` 一行：正确参数返回 true，路由当前使用的反向参数返回 false。识别到两处反向调用。

## 2. 已确认的源码矛盾：禁言标志被用作可见性放行条件

创建话题和回复流程把 `permission.ban_post` 为 true 当作禁止发言；[`lib/user/perm.ts`](https://github.com/bangumi/server-private/blob/e5340036c228e887185438feb579d8384dbf3954/lib/user/perm.ts) 的默认受限权限也将该标志设为 true。

但 [`lib/topic/display.ts:15,39`](https://github.com/bangumi/server-private/blob/e170542e22604b9af742b9bb14fb12d74e4b235e/lib/topic/display.ts#L39) 将它与管理权限作“或”运算，命中后扩大可见范围。

在原函数的离线测试中，虚构账号无管理权限，仅将 ban_post 从 false 改为 true，对另一虚构用户待审核内容的可见性从 false 变为 true。说明该分支与同仓库中禁言标志的用途矛盾；实际可达性和影响仍需官方在授权环境审查。本项目没有利用该行为，也不因此放宽客户端权限。

这处问题涉及可见性，不能拿来解释或修复登录过期，也不能用“把所有判断取反”代替逐项核对。

## 与 MuBangumi 当前兼容策略的关系

- `CommunityService` 已识别明确的成员拒绝：`NOT_JOIN_PRIVATE_GROUP_ERROR`，以及 HTTP 401/403 下的 `NOT_ALLOWED` 且消息包含 `join group first`。
- 仅上述明确拒绝允许转入经典网页提交，由网站重新校验实际成员资格；该错误不应当被误当成 OAuth 过期。
- 超时、响应丢失、5xx 不会触发第二次网页 POST，继续保留待确认状态；这与上游成员参数错误是不同层次的问题。
- 用户之前的“发帖结果未知”可能出现在网页兼容通道的提交之后，不能只凭发现这个上游 bug 就断定原帖没发出。

复测 `verification_loop_regression_test.dart`、`community_account_retry_test.dart`、`group_topic_submission_test.dart`，50 项通过。本轮没有修改软件运行逻辑，无需重启当前窗口，也未向官方发送 issue、PR 或其他消息。

本机原始证据与离线复现脚本位于被忽略的 `.dart_tool/maintenance/upstream-audit/`：`live-contract.json`、`offline-reproduction.json`、`reproduce.cjs` 及对应固定提交的源码。复现脚本执行时没有网络调用，不依赖真实账号。

在官方 issue/PR 中以函数名、成员资格和小组相关关键词检索，未找到明确对应这两处问题的修复记录；这不是“从未有人报告”的证明。已存在的回复数、隐私设置等 issue 不能混用为这两处缺陷的证据。
