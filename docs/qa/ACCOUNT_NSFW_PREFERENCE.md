# 账号 NSFW 偏好（2026-09-17）

入口：我的 → 设置 → Bangumi 账号 → 显示 NSFW 条目。

- GET `/p1/privacy` 读取真实账号偏好，PATCH 同一路径只提交 `preferences.showNsfwSubject`，不覆盖其他隐私设置。
- 使用已有 API 登录；权限以 `canSetNsfwSubject`、`allowNsfw` 为准。接口缺字段或读取失败时不冒充“关闭”。
- 保存期间禁止重复操作，以响应更新开关；无法确认结果时提供重新读取。账号切换后忽略旧请求，401 刷新不能把写入重试到新账号。
- 保存后清除社区内存缓存与动态磁盘快照，通知已打开的动态页面重新请求。变更前的迟到动态不能重新写入旧内容。
- 官方资格包括注册满 60 天及其他权限条件；客户端不自行推算。服务端隐私缓存约 60 秒，界面提示内容可能延迟生效、稍后下拉刷新。
- 不自动替用户开启或关闭。测试使用模拟响应，没有修改真实账号设置；现有搜索筛选规则不在本次变更范围内。

证据：线上 [P1 OpenAPI](https://next.bgm.tv/p1/openapi.json)、[隐私路由](https://github.com/bangumi/server-private/blob/master/routes/private/routes/privacy.ts)、[资格逻辑](https://github.com/bangumi/server-private/blob/master/lib/user/privacy.ts)。

验证：9 项新增账号偏好测试，加上社区服务、动态及原生操作回归，共 65 项通过。

6 个相关模块静态检查通过，Windows Release 构建成功并已启动供用户本地测试。

## 保存失败后的官网入口

- 用户报告点击后保存失败。本机只读查询返回 `canSetNsfwSubject=true`、`showNsfwSubject=false`，排除了当时的账号资格不足。
- 官方 [问题 #1787](https://github.com/bangumi/server-private/issues/1787) 仍未关闭；开发者确认隐私 PATCH 接口存在数据库表权限问题，可能返回 HTTP 500。未通过实际 PATCH 重现此账号的失败，避免诊断时改变用户设置。
- 已只读验证官网 `/settings` 页面含 `show_nsfw_subject` 开关；它不在 `/settings/privacy` 页面。
- 账号设置增加「在官网设置受限内容」按钮，经现有同账号网页登录核验后进入内嵌官网页面，由用户自行保存。返回后重新读取 P1 偏好并清理动态缓存，不把打开页面视为设置成功。
- 原生 PATCH 保留，失败时显示经过整理的 HTTP 状态；500 不再描述成账号权限问题，也不自动重试写入。
- 新增 500 错误、官网返回核验、旧值响应不误报成功、未保存直接返回四类回归。账号及社区相关 84 项测试通过，5 个模块静态检查通过。
