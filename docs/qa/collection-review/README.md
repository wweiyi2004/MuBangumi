# 收藏统计与回顾优化 · 2026-09-18

入口：收藏 → 统计与回顾。本次修改不涉及番键会统计。

## 视觉调整

根据用户截图反馈，概览与年度回顾均去掉大块渐变横幅。改用紧凑标题、无底色数字与细分隔线；年度回顾将年份选择与标题并排，摘要与统计口径缩短，月份标签明确显示“月”。作品预览在桌面采用双列，在手机和大字体下采用单列。

调整后运行 `flutter test test/insights_experience_test.dart test/collection_export_test.dart --dart-define=INSIGHT_SCREENSHOTS=true`：25 项通过；页面静态分析通过。检查了生成的桌面概览、年度回顾和手机截图。

## 行为

- 概览使用紧凑的 1–10 分柱状图，显示评分中位数；类型、状态、分数、标签以及高分/已完成/短评快捷入口均可查看对应收藏。
- 年度/月度回顾预览 10 条，提供完整列表，不再截断可访问的记录；支持评分优先、最近更新、最早更新排序，以及作品原名/中文名、标签、短评搜索。
- 完整列表按需构建条目，显示更新日期和完整短评；键盘弹出时收起排序栏，给搜索结果留出空间。
- 收藏同步期间允许进入，显示加载状态并随会话快照更新；账号退出或切换后移除当前统计页内容。
- 平均分、评分总数、分布、中位数均只接纳 1–10 分；无日期记录计入概览，不归入任何年份。
- 年度/月度按收藏的最后更新时间归档，**不是实际观看/游玩/完成日期或完整操作历史**。修改旧收藏可能改变归属年份；“当前已完成”是当前状态，不是当年完成数量。
- 原有全部收藏 JSON 保存/分享保持兼容。

## 验证

`flutter test test/collection_insights_test.dart test/insights_experience_test.dart test/collection_export_test.dart`：29 项通过。

覆盖无效/未评分、偶数/奇数样本中位数、无日期记录、时区边界、排序/搜索且不改变原数组、超过 10 条的完整记录浏览、类型内评分筛选、同步时进入并自动更新、退出账号清除、320 px 手机键盘/1.8 倍字体、1200 px 桌面和深浅主题、导出兼容。

相关 Dart 文件静态分析通过。截图由隔离测试数据生成，不含真实账号收藏：

- [桌面概览](overview-desktop.png)
- [桌面年度回顾](annual-desktop.png)
- [手机年度回顾](annual-phone.png)
- [完整记录](records.png)
- [手机大字体与键盘](records-keyboard.png)

Windows Release 和 Android Release 构建通过；本机 Windows 新版已启动且进程响应正常。构建产物及 SHA-256 见 [build-results.json](build-results.json)。

额外执行 `collection_shortcuts_test.dart` 时，3 个旧的 `profile … opens matching collections across all types` 测试在第 53 行寻找 `ProfileCollectionSummary` 失败；当前个人页已经使用 `ProfileHomeLayout`，失败发生于进入 `LibraryPage` 之前。本次未改个人页或这些旧用例，不据此声称全仓测试通过。

2.3.0+28 发布复核：上述旧用例已迁移到当前个人页入口；保留从收藏内筛选已完成的验证。全量 Flutter 测试 1131 项通过，详见本版本发布验收记录。

未进行手机真机安装或触摸测试，手机布局验证来自 Flutter widget tests。
