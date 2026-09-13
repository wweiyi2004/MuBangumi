# 安装包体积优化（build 25）

本轮仅调整普通 Flutter 的发布构建流程，不改变应用功能、账号存储、扫码识别方式，也未执行 Shorebird 或 GitHub 发布。

## 已落实

- `tool/build_release.ps1 -Target apk` 默认生成 ARM32、ARM64、x86_64 三份独立 APK，逐个移除旧目标并验证新产物，避免把旧包或不完整构建当作成功。
- 普通 APK、App Bundle、Windows 构建默认传入 `--split-debug-info`，每次在 Git 忽略的 `release-symbols/` 中保存独立符号目录；保留符号文件及产物 SHA256 对照，重复构建不会覆盖历史符号。
- 普通构建显式传入 `--tree-shake-icons`，不启用改变运行时类型名称的混淆。
- 支持 `-BuildName`、`-BuildNumber`，Shorebird 补丁禁止覆盖既有基线版本。这轮未改变 Shorebird 编译参数，避免影响已发布基线与补丁兼容性。
- CI 加入发布脚本回归检查；仓库隐私检查禁止追踪 `release-symbols/`。

## 测量口径

所有 MB 使用十进制（1 MB = 1,000,000 字节）。APK/ZIP 下载体积与解压后文件总量分别计算，不能把缓存或设备安装后占用混入下载大小。

Android 基准与优化构建均使用当前代码、普通 Flutter、版本 2.2.0+25、同一 OAuth 配置和签名。正式比较使用 ARM64 分架构基准 APK，避免把旧版通用包与新代码分包的差异全部归功于本轮优化。

`--analyze-size` 单架构分析构建仍可能带入其他架构的插件库；分析包仅用于依赖归因，不用于下载体积对照或分发。分析文件保留在本地 `.dart_tool/size25-analysis/`，不上传。

### 同代码实测

| 指标 | 基准 | 优化后 | 减少 |
| --- | ---: | ---: | ---: |
| Android ARM64 APK | 36,534,886 B（36.53 MB） | 34,765,426 B（34.77 MB） | 1.77 MB，4.8% |
| Windows ZIP | 19,398,607 B（19.40 MB） | 18,312,522 B（18.31 MB） | 1.09 MB，5.6% |
| Windows 解压文件总量 | 45,085,074 B（45.09 MB） | 42,660,242 B（42.66 MB） | 2.42 MB，5.4% |

ARM64 的 `libapp.so` 从 14,418,832 B 降至 12,649,360 B；Windows 的 `data/app.so` 从 15,811,472 B 降至 13,386,640 B。Windows 图标字体仍为 1,645,184 B，未将未落实的裁剪计入收益。

候选包在 `dist/size-build25/`，版本 2.2.0+25：

- `MuBangumi-2.2.0-build25-android-arm64-v8a.apk`：34,765,426 B，versionCode 2025。
- `MuBangumi-2.2.0-build25-android-armeabi-v7a.apk`：31,126,756 B，versionCode 1025。
- `MuBangumi-2.2.0-build25-android-x86_64.apk`：37,403,249 B，versionCode 4025。
- `MuBangumi-2.2.0-build25-windows-x64.zip`：18,312,522 B。
- `checksums.json`：四个产物的大小、SHA256 与版本；Windows 另记 `data/app.so` 的哈希，以对应独立符号。

Android 符号保存于 `release-symbols/apk-7f72d7ff14f7497c92e1636aabba16e5/`，Windows 符号保存于 `release-symbols/windows-49dd79c7396e441196a3aa55b63eb27f/`。仅本地保存，不表示已完成异地备份。

## 取舍

- 保留扫码的内置 ML Kit 模型。ARM64 包中识别本机库与模型合计约 5.83 MB；改为动态下载会增加首次使用的网络与服务依赖，本轮不改变该行为。
- AOT 归因中 Flutter 框架约 4 MB、项目代码约 2 MB、图片处理约 747 KB、时区约 265 KB、HTML 约 234 KB、ZXing 约 134 KB；这是分析工具的符号归因口径，不等于删除依赖后可节省的包大小。
- Windows 现有 Flutter SDK 的 `tool_backend.dart` 给 `TreeShakeIcons` 传递带引号的值，而裁剪器检查字面量 `true`，导致 CLI 开关未实际裁剪字体。本轮不修改开发机 SDK、不手工删除字形；Windows 的主要优化依靠符号分离。将来升级 SDK 后需再验证图标字体是否缩小。
- 普通 Flutter 候选包不具备 Shorebird 热更新能力。已有 Shorebird 发布方式保留，不把普通包冒充为热更新基线。

## 验证

发布脚本回归覆盖分架构输出、缺失产物不能复用旧包、唯一符号目录、产物哈希、其他目标不携带 APK 专用参数、缺失符号、编译失败、Shorebird 参数与补丁版本约束。Windows 打包隐私防护也单独回归。

本轮未新增业务代码，因此不重复既有全量业务测试；以真实 Release 构建、APK 签名/Manifest、包内容和打包脚本验证为主。未进行本轮候选包的真机安装验收。

实测验证：8 组发布构建回归与 13 项 Windows 包安全检查通过；仓库隐私检查通过。三份 APK 均通过 `apksigner verify`，包名、versionName、各架构 versionCode 正确，无 debuggable 标记，保留 text/plain 分享入口；每包仅有对应架构的本机库，无调试符号、私有数据文件或分享诊断入口。Windows 打包通过目录与 ZIP 内容防护检查。最终产物的 SHA256 与校验记录、对应符号记录一致。
