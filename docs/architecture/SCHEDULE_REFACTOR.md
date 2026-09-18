# 新番表职责拆分：第四阶段

日期：2026-09-14。继续在 `refactor/session-responsibilities` 分支进行。

## 本轮边界

原 `schedule_page.dart` 同时维护页面订阅、搜索请求、季度选择、拖拽、条目卡片和操作菜单。本轮把这些职责拆入 `lib/features/schedule/`，页面入口从 2,137 行缩减到 353 行。

| 文件 | 职责 |
| --- | --- |
| `application/schedule_search_controller.dart` | 搜索防抖、立即提交、作品类型切换、旧请求失效、放送日加载与超时 |
| `presentation/schedule_search_sheet.dart` | 搜索输入与结果、自动/手动星期选择、连续加入新番表 |
| `presentation/schedule_board.dart` | 待安排区域、七天网格、拖拽位置与季度校验、拖到删除区 |
| `presentation/schedule_course_cell.dart` | 不同宽度的作品卡片、封面、进度、未读和提醒标记、拖拽预览 |
| `presentation/schedule_header.dart` | 季度快捷选择与工具栏的宽窄屏展示 |
| `presentation/schedule_season_dialog.dart` | 新建/打开季度弹窗，通过回调提交选中的季度 |
| `presentation/schedule_item_actions.dart` | 共用的改期、删除、进度与撤销、提醒及 RSS 菜单 |

课表、卡片和季度组件不读取 Provider；数据和操作回调由页面提供。搜索控制器不依赖 Widget、Riverpod、账号状态或新番表存储，弹窗创建时监听，销毁时取消防抖并停止发布结果。API 通过函数获取，重试仍使用当前线路对应的实例。

页面继续负责会话、新番表、RSS、日期与视图偏好的订阅，以及导航和操作接线。菜单与搜索弹窗属于界面集成层，继续读取原有 Provider；RSS 弹窗仍在 `screens/rss_sheets.dart`，没有为目录迁移再造服务层。原 `showScheduleItemActions` 入口通过页面文件转导出，调用保持兼容。

## 保持与修正

- 三种视图、季度快捷添加、官方放送日与手动星期选择、连续添加等交互保持。
- 拖拽带有季度身份，换季度后旧拖拽不能修改新表；操作菜单返回后仍检查季度、加载/保存状态和条目是否存在，更新进度还检查账号。
- 放送日查询仍限时 8 秒，失败或超时后允许加入待安排或手动排期，不阻塞搜索。
- 输入变化立即作废旧请求；清空关键词清理结果、错误与加载状态；关闭弹窗后迟到结果不发布。
- 修正防抖期间切换作品类型仍留下旧计时器的问题：类型切换与回车提交统一取消计时器并立即搜索，避免重复请求。
- 新建季度弹窗返回时增加页面存活检查。
- 本轮不改数据库、账号凭据格式、提醒调度、RSS 抓取或收藏上传协议。

## 验证

新增 `schedule_search_controller_test.dart` 8 项，覆盖防抖与立即提交、切类型、关键词变化时旧响应、清空搜索、换 API 后重试、销毁后的请求、有效放送日过滤、放送日超时。

- 既有新番表体验、视图、控制器及提醒弹窗测试 52 项通过。
- 三种视图的渲染测试 12 项通过，覆盖 320/390/1200 宽度、1.0/1.8 字号、浅色/深色主题。36 张截图与保存的重构前截图逐像素一致；已查看手机大字号和桌面深色课表。
- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub --reporter expanded`：940 项全部通过，含本轮新增 8 项。
- `git diff --check`：通过。

截图及日志位于忽略的 `.dart_tool/`。本轮为本地 Flutter 自动化与渲染验证，未进行 Windows/Android 原生真机验收，未构建或发布安装包。

## 后续范围

站内短信页面以及详情页的评论分页、好友和补充资料请求已在[第五阶段](PM_AND_SUBJECT_REQUESTS_REFACTOR.md)完成整理。现有 `schedule_controller.dart` 已负责持久化与提醒同步，本轮保留其边界；不为了统一目录移动整套存储和通知模块。
