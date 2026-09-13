# 新番表季度选番快捷入口 · build 27

日期：2026-09-13，版本 2.2.0+27，Android / Windows。

## 使用路径

- 手机：新番表 → 季度旁“选番”。
- 桌面：新番表 → “挑选本季新番”。
- 默认读取当前打开的季度，弹层明确显示年份、季度和月份范围。需要另一个季度时，先关闭选番，再切换新番表季度。
- 展示封面、标题、开播日期和评分；支持逐部勾选、全选已加载、清空选择和加载更多。已在该表的作品不可重复选择。
- 选“按放送日安排”时匹配当前官方每日放送，未收录或接口失败时放入待安排；也可主动选择全部待安排。原有搜索加入继续保留。
- 批量添加仅写本机新番表，不改官网收藏；新增提醒默认关闭。已有条目的顺序、星期、备注和提醒保持原样。

## 实现与验证

- 复用 `BangumiApi.browseSubjects`。官方 API 的 `month` 参数是月份，因此并行读取该季度的三个月，各自维护分页偏移。整批请求失败不推进偏移，已加载内容与勾选保留，重试不漏页。作品按 ID 去重。
- 复用 `ScheduleController.addBatchToSeason`，扩展按作品指定星期；仍为一次批量本机保存和一次提醒协调。保存失败可重试；按星期单独累积顺序。
- 选番会话绑定打开时的季度和账号，账号或季度变化后拒绝旧列表添加，迟到网络响应不覆盖目标。保存中锁定重复点击和关闭。
- 900 项全量 Flutter 测试通过；Dart 静态分析无问题。
- 覆盖三个月请求、多选添加、分页失败原位重试、迟到响应、已有提醒保留、重复添加、分日排序及失败回滚。
- 手机 320px / 1.0 与 1.8 倍字体布局截图已检查；原有 320px × 640px 大字体提醒入口及桌面周表回归通过。
- 公开接口只读验证：2026 年 7、8、9 月均返回当月条目；记录在 `.dart_tool/season27-public-api.json`。数量会随 Bangumi 数据维护变化。
- 原生窗口控制服务不可用，本轮不能声称做过 Windows 界面点击验收；编译、包检查及 Flutter 组件测试分别记录。

接口依据：[Bangumi 官方 OpenAPI](https://github.com/bangumi/server/blob/master/openapi/v0.yaml)，`GET /v0/subjects` 的年份、月份和分页参数。

截图：`.dart_tool/season27_picker_320_1.0.png`、`.dart_tool/season27_picker_320_1.8.png`。

## 候选包

产物位于 `dist/season-build27/`，文件名均含 build27，SHA256 记录为同目录 `checksums.json`。正式发布前复查见 `RELEASE_2.2.0_BUILD27.md`。

| 平台 | 大小（十进制 MB） |
| --- | ---: |
| android-arm64-v8a.apk | 34.90 |
| android-armeabi-v7a.apk | 31.21 |
| android-x86_64.apk | 37.53 |
| windows-x64.zip | 18.35 |

Android 版本号分别为 ARM32 1027、ARM64 2027、x86_64 4027，APK 签名和内容检查通过。Windows 版本为 2.2.0+27，目录及 ZIP 白名单检查通过；ZIP 内 EXE / app.so 与构建记录一致，AOT 产物包含本季选番入口。仓库隐私文件布局检查通过。

调试符号独立保留：`release-symbols/apk-2ec0a4decf604c9d999aee8835bf89de`、`release-symbols/windows-407c59ee336a439a92346871850b155e`。新版 Windows 已启动供用户验收，启动进程不代表已完成原生页面交互验收。
