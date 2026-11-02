# 服务端、网站与研究模块审计（2026-10-27）

本次范围为 `packages/banjian_server`、`website`、`tool/recommend_dataset`、`tool/semantic_retrieval`。保留审计前已有改动；不访问运行数据库、浏览器资料、OAuth 文件或模型，不执行认证真实消息/帖子写入，不发布。

## 修复

- `packages/banjian_server/web/app.js`：管理端创建/打开/切换活动先保存 `{id}`，首次状态请求失败时，原渲染直接读取缺失的 `rounds`，抛出 TypeError 并中断重试安排。现在展示恢复提示，安全读取当前轮次，待完整快照恢复再渲染管理面板。生命周期回归在修复前实际失败，修复后通过。
- `tool/recommend_dataset/src/http_client.py`：耗尽重试的 429，以及 401/403 等可恢复错误，原先被归为永久不可用，采集器随后会把条目标为 `permanent`，导致后续恢复和导出排除它们。现在仅将 404/410 归为不可用，保留项目既有 404 策略。
- 同一 HTTP 客户端原先在 JSON 解码前递增成功计数，使 200 + 无效 JSON 同时计入成功和失败。现在仅在成功解码后计入成功。
- 首轮 Full 发现网站依赖审计新增两项高危。按官方修复版本定向更新 `undici` 7.29.1 → 7.30.1、`zod` 4.4.3 → 4.6.7，以及有中低危公告的 `fast-uri` 3.1.8 → 3.1.9。声明仅调整现有 undici override，锁文件相对本轮更新前备份仅三个 package 条目变化。保留原 braces 补丁及其他依赖；没有新增忽略、豁免或降级 Cloudflare 插件。更新前文件备份位于 `.dart_tool/audit-2026-10-27`。

## 针对性验证

固定运行时来自 `tool/toolchain.json`，通过 `tool/toolchain.ps1` 解析，未升级全局工具。

- 浏览器协议共享夹具及生命周期：`node --test packages/banjian_server/test/room_protocol_test.cjs`，协议断言及 4 项生命周期测试通过。该入口已 require 生命周期测试，无需额外接入验证脚本。
- 推荐采集 HTTP/恢复：`pytest tool/recommend_dataset/tests/test_http.py tool/recommend_dataset/tests/test_backfill.py -q`，31 项通过；仅使用 localhost 合成服务与临时测试数据。
- 语义研究：`pytest tool/semantic_retrieval/tests -q`，43 项通过；未修改该模块。
- 网站依赖更新后 `typecheck`、`lint`、`audit:security` 通过。安全补丁回归 12 项通过，原始 npm audit 为所有严重级别零漏洞；网站构建与统一验证结果以主审计后续执行的记录为准。

## 审计结论与边界

已检查服务端 HTTP/WS 认证、来源校验、封面来源限制、匿名导出与浏览器重连路径；网站检查 Worker、静态发布配置、演示组件及现有依赖安全检查。未发现需要猜测修改的额外确定问题。

既有研究数据库中可能已经被旧逻辑误标为 `permanent` 的记录没有自动迁移，本次未读取或改写这些运行数据。404 不一定代表永久消失，但此处保留已有采集策略，避免扩大行为变化。设备、真实多机局域网、公网代理、云部署与模型推理验收未执行。

## 外部依据

- [RFC 6585 §4](https://www.rfc-editor.org/rfc/rfc6585.html#section-4)：429 表示限流，可携带 Retry-After；耗尽本轮重试不意味着条目永久消失。
- [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#name-410-gone)：410 表示资源可能永久不可用，404 不明确区分临时与永久。
- [MDN WebSocket 客户端指南](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_client_applications)：以连接生命周期驱动发送/关闭处理，HTTPS 页面使用 wss。
- [Requests 官方高级用法](https://requests.readthedocs.io/en/stable/user/advanced/)：Session 重试及连接/读取超时的语义；现有采集客户端已设置超时和退避。
- [Undici 高危公告](https://github.com/advisories/GHSA-xjj6-f33q-929c)：7.30.1 修复过多 content-encoding 导致进程崩溃的问题；现有 Node 22.23.2 满足其 Node >=20.18.1 要求。
- [Zod 高危公告](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5)：4.6.6 起修复集合验证耗尽内存；本轮定向更新解析到同一 4.6 系列的 [4.6.7](https://github.com/colinhacks/zod/releases/tag/v4.6.7)，符合上游调用方的 `^4.0.0` 范围。
- [fast-uri 3.1.9 官方发布](https://github.com/fastify/fast-uri/releases/tag/v3.1.9)：保持原主版本，修复 URI 解析安全问题。
