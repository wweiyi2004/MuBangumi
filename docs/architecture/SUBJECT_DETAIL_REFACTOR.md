# 番剧详情页拆分：第三阶段

日期：2026-09-14。继续在 `refactor/session-responsibilities` 分支进行。

## 本轮边界

原详情页将二十多个 Widget 类和章节网络/缓存加载放在同一文件。本轮将展示区块提取到 `lib/features/subject_detail/presentation/`，章节读取提取到 `application/`；`SubjectDetailScreen` 构造参数、导航入口和页面交互保持兼容。

| 文件 | 职责 |
| --- | --- |
| `subject_detail_header.dart` | 封面、标题、条目属性、标签和收藏操作入口 |
| `subject_rating_panel.dart` | 评分分布、争议度和收藏人数 |
| `subject_friends_panel.dart` | 好友收藏与评论展开状态展示；用户跳转由页面回调提供 |
| `subject_episode_grid.dart` | 章节网格、60 项分页、已看/未看及保存中的禁用状态 |
| `subject_moegirl_panel.dart` | 萌娘百科补充资料、原文入口与错误展示 |
| `subject_expandable_content.dart` | 简介和长列表的展开/收起 |
| `subject_meta_sections.dart` | 角色、制作人员、关联作品的横向卡片和区块空/错误状态 |
| `subject_episode_loader.dart` | 公共章节或个人章节进度加载、并行缓存恢复、重试与请求生命周期 |

展示组件不读取全局会话或发起 Bangumi 数据请求，操作通过参数和回调连接页面。章节加载器依赖收藏模块的只读接口 `EpisodeCollectionReader`；`SessionController` 和 `CollectionEditor` 实现此接口，因此加载器不导入会话状态，也不需要知道收藏编辑如何实现。

## 需要保持的行为

- 章节请求与条目信息、人物资料等请求独立执行，缓慢章节不阻塞其他内容。
- 缓存读取和网络请求并行；网络结果已生效后，迟到的缓存读取或本地合并结果都不得覆盖它。
- 每次加载绑定请求批次和账号 ID、用户名、登录批次。新请求、账号切换、同名账号重新登录和页面销毁都会阻止旧结果发布。
- 离线时保留已恢复的章节进度，显示重试状态；新重试清理旧错误。
- 未收藏条目使用公共章节接口，不读取个人章节快照。
- 收藏编辑后的轻量刷新通过同一个加载器执行，避免与较早的加载交叉覆盖；它不弹出新错误或显示加载占位。
- 页面仍负责乐观章节反馈、保存中的按钮状态、撤销提示以及导航。未改数据库、网络协议或账号凭据格式。

## 验证

新增 `subject_episode_loader_test.dart` 8 项，覆盖缓存读取/合并迟到、同名重登、新请求、销毁、离线重试、公共章节与轻量刷新。

新增 `subject_detail_panels_test.dart` 3 项，覆盖章节分页和操作回调，以及 320/1200 宽度下角色、制作人员与关联作品入口。

最终检查：

- 详情页加载、好友评论、资料分组、进度界面等既有测试 30 项通过。
- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub --reporter expanded`：932 项全部通过，含本轮新增 11 项。
- `flutter test --no-pub --dart-define=UX_SCREENSHOTS=true test/subject_detail_loading_test.dart`：6 项通过，生成详情页及短评输入截图。
- 320 像素宽度、字号 1.0/1.8 的详情页截图与保存的重构前截图逐像素一致；已检查大字号详情页和短评输入截图，短评焦点与模拟键盘显示的原断言通过。
- `git diff --check`：通过。
- 详情页入口从 2,581 行缩减至 965 行，七个展示文件按内容分组管理。

截图保存在忽略的 `.dart_tool/mobile24_subject_320_*.png`、`.dart_tool/mobile24_comment_320_*.png`。本轮为 Flutter 自动化及渲染验证，尚未做真实账号授权或原生真机验收，未构建和发布新安装包。

## 后续范围

新番表已在[第四阶段](SCHEDULE_REFACTOR.md)拆出搜索和展示组件。[第五阶段](PM_AND_SUBJECT_REQUESTS_REFACTOR.md)已完成站内短信页面拆分，并提取详情页的条目信息、评论分页、好友查询和其他补充资料请求。详情页入口保留布局、导航、章节乐观反馈和交互协调。
