# Bangumi 剩余社区能力核查

2026-09-17：已确认部分的实现进展见 [原生功能实现](COMMUNITY_NATIVE_FEATURES.md)。以下保留本次接口核查时的证据与边界。

核查日期：2026-09-16。此次仅核查，没有提交发帖、编辑、删除、收藏、加组或上传请求，也未改变应用功能。

## 证据范围

- 读取了生产站点 [P1 OpenAPI](https://next.bgm.tv/p1/openapi.json)，确认线上声明的路径、方法和参数，而非只凭仓库源码判断已部署。
- 读取官方 `bangumi/server-private` 提交 `dcb644e91f581621a59bd6a4c4e9b16a310a54e9`（2026-09-15T17:56:13Z），用于核查处理逻辑和权限。
- 对照当前官方 [V0 OpenAPI](https://github.com/bangumi/server/blob/master/openapi/v0.yaml)、官网公开页面、官网脚本和本项目实现。
- 实测仅为公开 GET；登录后的上传、管理表单及真实写操作尚未验证。“接口存在”不等于已完成端到端验收。
- 生产 P1 文档本地 JSON 快照（PowerShell 重新序列化后的文件）SHA256：`86EB8805AC64E4A959F1ED23C8980EA3D584B3D7B193B4EF0F380A1596438996`。

## 逐项结论

| 功能 | 核查结果 | 可采用的实现方式 | 仍需验证 |
| --- | --- | --- | --- |
| 人物、角色收藏 / 取消收藏 | 线上 P1 和公开 V0 都有接口 | 原生按钮、状态读取、操作后刷新收藏数与列表 | 登录账号真实写入、重复操作、失败恢复 |
| 时光机对象点击跳转 | 动态 memo 有对象 ID，项目已有条目 / 人物 / 角色详情页 | 保留结构化对象到 UI，再接原生导航 | 单条与批量动态、接口未返回对象详情的占位 |
| 时光机贴贴 | 线上有添加 / 取消接口；服务端只接受状态类动态 | 对支持的动态显示贴贴入口 | 权限、429、状态刷新；不能对所有收藏动态套用此接口 |
| 删除自己的动态 | 线上有 DELETE，服务端核对动态作者 | 原生确认弹窗与删除后刷新 | 删除会一并删除该动态的回复；真实操作待验证 |
| 用户日志列表、正文、发布、编辑 | 线上有列表分页、详情、POST 和 PATCH | 可做原生页面与编辑器，沿用 Turnstile | 发布、仅好友可见、标签和关联条目的写入闭环 |
| 删除整篇日志 | 未在生产 P1 文档或所查后端路由中找到对应 DELETE | 现阶段保留官网流程；若做原生表单适配，先核对作者登录页面 | 删除日志不能用“删除日志评论”接口替代 |
| 删除整个小组 / 条目话题 | 所查线上接口只有话题编辑、回复删除，没有整个话题删除 | 现阶段使用官网入口 | 删除首楼只改变回复状态，不等同删除话题 |
| 创建 / 管理 / 加入 / 退出小组 | 未找到这些写操作的生产 P1 路由；项目现有加退组已经走官网 | 官网流程可继续使用；原生适配需核对对应登录表单 | 管理员 / 普通成员权限、CSRF、提交结果；不能承诺已能纯 API 实现 |
| 本地图片上传 | 官网脚本确实调用 `/blog/upload_photo`；未找到通用 P1 帖子图片上传接口 | 可进一步适配官网的日志图片上传通道 | 登录会话、multipart 字段、CSRF、服务端格式和大小限制、图片最终引用与归属 |
| BBCode 补齐 | 官网文档明确支持颜色、字号等；属于客户端渲染工作 | 可继续补颜色 / 对齐 / 图片尺寸等，配合嵌套与长文本测试 | 复杂 HTML 回退、选择复制、布局和剧透边界；不能直接声称全语法一致 |
| 超展开 200 条以后的完整历史 | P1 聚合无 offset / until；官网人物聚合 `page=1` 和 `page=2` 实测返回同一组 100 条 | 目前保留最近讨论；指定小组和条目已有各自分页接口 | 未找到完整聚合历史的可用分页来源，不能承诺仅改客户端就能补齐 |
| 打包与实际验证 | 工程已有平台构建流程，本轮没有构建新包或进行设备验证 | 后续构建目标平台、实际验证读写及账号切换 | 自动化测试、公开读取和源码核查不能替代设备与真实账号验收 |

## 已核实的接口

### 收藏

- `GET /p1/collections/characters`、`GET /p1/collections/persons`：当前用户列表，支持 limit / offset。
- `PUT`、`DELETE /p1/collections/characters/{characterID}`。
- `PUT`、`DELETE /p1/collections/persons/{personID}`。
- V0 备选：`POST`、`DELETE /v0/characters/{character_id}/collect`，以及 `/v0/persons/{person_id}/collect`，文档声明需要收藏写权限。

来源：[收藏路由](https://github.com/bangumi/server-private/blob/dcb644e91f581621a59bd6a4c4e9b16a310a54e9/routes/private/routes/collection.ts)、[V0 文档](https://github.com/bangumi/server/blob/master/openapi/v0.yaml)。

### 时光机

- `PUT /p1/timeline/{timelineID}/like`，请求体 `{ "value": 表情编号 }`。
- `DELETE /p1/timeline/{timelineID}/like`。
- `DELETE /p1/timeline/{timelineID}`：要求作者身份；实现中同时删除相关时间线评论。
- 服务端贴贴校验 `cat == TimelineCat.Status`；不同于条目收藏短评的贴贴接口。

来源：[时间线路由](https://github.com/bangumi/server-private/blob/dcb644e91f581621a59bd6a4c4e9b16a310a54e9/routes/private/routes/timeline.ts)。

### 日志

- `GET /p1/users/{username}/blogs?limit=20&offset=0`：按用户的日志列表，不是全站日志流。
- `GET /p1/blogs/{entryID}`。
- `POST /p1/blogs`：标题、BBCode 正文，支持 tags / public / subjectIDs，需要 Turnstile；当前 schema 没有上传文件字段。
- `PATCH /p1/blogs/{entryID}`：编辑自己的日志，可选更新标题、正文、标签、可见性与关联条目。
- 不存在于本次所查路径中的：`DELETE /p1/blogs/{entryID}`。
- 实测 `GET /p1/users/sai/blogs?limit=2&offset=0` 返回 HTTP 200、2 条数据；未提交 POST / PATCH。

来源：[日志路由](https://github.com/bangumi/server-private/blob/dcb644e91f581621a59bd6a4c4e9b16a310a54e9/routes/private/routes/blog.ts)、[用户日志列表](https://github.com/bangumi/server-private/blob/dcb644e91f581621a59bd6a4c4e9b16a310a54e9/routes/private/routes/user.ts)。

### 图片上传

在 [官网脚本 r771](https://bgm.tv/min/g=js?r771) 的 `chiiLib.blog.uploader` 中确认：

- Dropzone 目标为 `/blog/upload_photo`。
- 前端设置 `maxFilesize: 2`，接受图片；这是前端设置，不代表已验证服务端限制。
- 成功回调读取 `photo_id`、`filename`，并向日志表单添加 `upload_photo[]`。
- 此次没有调用上传地址，也没有上传任何文件。公开组件页面 `/dev/app/5237` 在匿名访问时要求登录，没有将其内容作为已核实实现依据。
- 维基封面 / 人物头像上传具有不同语义与权限，不能当成通用图床使用。

### 历史聚合

- 生产 `GET /p1/rakuen/topics` 只声明 type、limit，limit 最大 200。
- 匿名读取官网人物聚合 `type=mono&filter=person&page=1` 和 `page=2`：各 100 个 `item_prsn_*`，ID 序列完全相同；公开页面未发现历史翻页入口。
- 该结果只证明这个 `page` 参数不能用于历史翻页，不证明网站没有任何其他内部接口。
- “在官网查看更多讨论”不应被解释为“官网保证提供超出 200 条的完整历史”。之前关于“适配官网分页即可突破限制”的可能性，当前尚未得到证实。

来源：[聚合路由](https://github.com/bangumi/server-private/blob/dcb644e91f581621a59bd6a4c4e9b16a310a54e9/routes/private/routes/rakuen.ts)、[官网人物聚合](https://bgm.tv/rakuen/topiclist?type=mono&filter=person)。

## 可执行顺序

1. 接入已确认的收藏、时光机导航 / 贴贴 / 删除、用户日志列表 / 发布 / 编辑。
2. 补正文颜色等客户端能力，以及模拟失败、账号切换、重复提交测试。
3. 核对登录后的官网上传与管理表单，再决定是否提供原生界面；保留官网入口。
4. 超展开完整历史单独列为待证实能力，不把重复返回第一页包装成历史分页。
5. 完成目标平台打包与真实账号验收后，再判断是否达到稳定发布要求。
