# 社区功能补全（2026-09-16）

后续接口核查见 [剩余社区能力核查](COMMUNITY_CAPABILITY_AUDIT.md)。其中，官网入口不代表已确认能获取超过 200 条的完整聚合历史；实测官网人物聚合的 `page=2` 与第一页相同。

## 范围

| 功能 | 实现与边界 |
| --- | --- |
| 小组历史话题、完整成员 | 小组详情进入“全部话题 / 全部成员”，按接口原始条数推进 offset，按 ID 去重，保留失败前的内容并允许重试 |
| 条目新讨论 | 条目详情“发讨论”，支持标题、BBCode、账号隔离草稿和 Turnstile 验证 |
| 自己的话题 | 小组 / 条目正文菜单可编辑标题和正文；删除整个话题转官网，不能用删除首楼接口代替删除话题 |
| 自己的回复 | 小组 / 条目 / 章节 / 角色 / 人物 / 日志支持编辑和删除；只对原始数据可编辑且作者为当前账号的内容显示菜单，删除前确认 |
| 评论回复 | 章节 / 角色 / 人物 / 日志接入 P1 评论与楼中楼；第一条评论不会被误当成话题首楼 |
| 贴贴 | 小组 / 条目 / 章节原生支持；人物 / 角色 / 日志未接入写接口，不显示可操作按钮 |
| 超展开分类 | 保留原有条目、小组分页；增加综合 / 章节 / 角色 / 人物最新讨论 |
| 聚合接口限制 | `/p1/rakuen/topics` 只有 limit，没有 offset；获取最多 200 条并本地分页，末尾明确显示“最近 N 个讨论”，保留官网入口 |
| 角色、人物入口 | 详情页工具栏增加讨论入口 |
| BBCode 正文 | 使用 P1 原始正文渲染粗体、斜体、下划线、删除线、引用、代码、链接、原位图片和剧透遮罩，支持长内容展开；编辑器可预览 |

## 仍依赖官网或未覆盖

- 加入 / 退出小组继续使用已有的应用内官网流程。
- 小组创建、资料编辑、成员管理、置顶等尚未提供原生管理界面。
- 删除整个话题继续走官网；日志本体的创建、编辑、删除不在此次范围内。
- 聚合分类不提供日志列表；已有日志链接可进入原生日志评论。
- HTML 回退内容仍使用既有的文本和图片解析。BBCode 并非官网全部语法的逐像素复现，复杂 HTML、字体颜色、对齐与图片上传尚未覆盖。

## 验证

- 社区、话题阅读和条目详情整组回归测试通过（136 项，包含新增功能与边界测试）。
- `test/community_expansion_test.dart`：请求路径和载荷、作者权限、账号切换、主题与回复区别、评论楼层、聚合列表分页、小组分页与重试。
- `test/community_rich_content_test.dart`：嵌套样式、HTTP(S) 链接、图文顺序、代码原文、剧透显示 / 隐藏、编辑预填、跳过不需要的验证、窄屏大字体菜单。
- 公开接口只读校验：章节、角色、人物各取 3 个聚合条目，实际评论响应均能解析正文与楼层。
- 写操作仅用拦截的模拟接口验证，没有向真实账号发帖、改帖或删帖。
- 本次修改为源码，尚未生成或发布新的安装包。

### 稳定性复查

复现并修复了四个边界问题，均先通过失败测试确认，再修复并重跑整组测试：

1. 有旧列表时刷新失败，重试错误地加载下一页；现在重试原先失败的首页刷新。
2. 链接内部的剧透标签被展平成文字，导致提前显示；现在保留嵌套结构，只有点击“显示剧透”后才显示。
3. 引用在极窄可用宽度下触发范围错误；现在允许引用内部宽度收缩至零。
4. 小组列表切换账号后残留旧内容；现在监听账号变化、清空列表、重新获取首页，并使旧请求失效。

尚未完成新安装包的设备实测和真实账号的发帖 / 编辑 / 删除闭环，因此这些自动化结果不能等同于线上稳定性保证。

## 接口依据

- [小组讨论接口](https://github.com/bangumi/server-private/blob/master/routes/private/routes/group.ts)
- [条目讨论接口](https://github.com/bangumi/server-private/blob/master/routes/private/routes/subject.ts)
- [超展开聚合接口](https://github.com/bangumi/server-private/blob/master/routes/private/routes/rakuen.ts)
- [章节评论接口](https://github.com/bangumi/server-private/blob/master/routes/private/routes/episode.ts)
- [角色评论接口](https://github.com/bangumi/server-private/blob/master/routes/private/routes/character.ts)
- [人物评论接口](https://github.com/bangumi/server-private/blob/master/routes/private/routes/person.ts)
- [日志评论接口](https://github.com/bangumi/server-private/blob/master/routes/private/routes/blog.ts)
