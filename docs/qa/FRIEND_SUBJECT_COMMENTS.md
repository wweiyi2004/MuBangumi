# 番剧详情：好友收藏与评论

2026-09-12。用户希望在同一处查看好友对每个番剧的评论和收藏。

原页面仅用头像标签显示好友姓名、收藏状态和评分。现在“好友收藏与评论”按好友展示独立条目：头像和昵称、收藏状态、评分、对应收藏的短评。点击头像/昵称区域仍进入好友主页；评论可以选择复制，超过四行时可展开、收起。没有评论的好友保留收藏信息，未评分不显示零分。整个区块也可以收起，再次展开复用已加载数据。

评论来自已有 `getUserSubjectCollection` 响应的 `comment` 字段，随 `FriendSubjectStatus` 一起传递；不从公共吐槽列表按昵称匹配，不为评论额外发送请求。原有公共“吐槽”区域继续展示公共评论。当前好友取样上限仍沿用原实现的 12 位，本次没有改为扫描全部好友。

刷新详情或切换会话后，旧好友请求不能回写当前页面；加载失败提供重试入口。

验证：`flutter test --no-pub --dart-define=UX_SCREENSHOTS=true test/friend_subject_collection_test.dart test/subject_detail_loading_test.dart`，9 项通过（含截图）。覆盖同一好友的数据关联、空评论/未评分、320 宽与两倍字号、长评论展开不触发主页导航，以及详情各区块独立加载。已查看实际渲染截图 `.dart_tool/friend-collection-preview.png`。

`dart analyze lib` 和新测试文件静态检查均无问题。Flutter analyze 的分析服务未结束，本轮改用 Dart 分析命令完成检查。

Windows `2.2.0+21` 已从正式 `lib/main.dart` 构建并打开，包含已经验收的毛玻璃修复，关闭临时背景诊断编译开关。包 `dist/friend-collection-build21/MuBangumi-2.2.0-windows-x64.zip` 的仅运行文件检查通过，解压后的 EXE/app.so 摘要与构建输出一致。尚未发布 GitHub，实际好友数据的用户验收待确认。
