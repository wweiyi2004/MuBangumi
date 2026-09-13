# v2.2.0+27 发布前检查

日期：2026-09-13。发布使用用户已试用的 build 27 候选包，应用代码与候选构建保持一致，仅将源码 pubspec 版本由构建时覆盖的 2.2.0+12 对齐到实际产物 2.2.0+27。

- 4 个附件 SHA256 与候选构建及打包记录一致。
- Windows ZIP 34 个条目，3 个 APK 各 363 个条目；逐项检查私有路径和 SQLite 文件头，未发现数据库、账号缓存、Cookie、WebView 资料或登录凭据文件。
- Windows 运行文件白名单检查通过；13 项打包防护回归通过。
- 对发布源码快照和 `origin/main..HEAD` 中的 19 个开发提交使用 Gitleaks 8.30.1 扫描，结果均为 0 条发现；扫描报告只保存在本机，不随安装包上传。
- 900 项 Flutter 测试和 Dart 静态分析通过，记录见本轮新番表 QA。源码版本号对齐不改变候选包。
- 本地 OAuth 配置、签名材料、运行目录和调试符号不纳入 Git；不上传包含本机绝对路径的原始 checksums.json，仅分发文件名与 SHA256。

以下是发布附件的校验值：

```
e60d2996c0584c92f3f939c0faec120b93de88edb6afd747486e834051fa3185  MuBangumi-2.2.0-build27-android-arm64-v8a.apk
9ccbd6ad16d9d720d2dea86fa36401c81d20d5ba228b509cff88df0eea0b3704  MuBangumi-2.2.0-build27-android-armeabi-v7a.apk
09ca3da89a1585ba408126f06b928e8acb55cae35c50d0d3c3c69abff61a25a7  MuBangumi-2.2.0-build27-android-x86_64.apk
e317a944a283cb096c24dacf764991cad86b1eb9280076c2da15c529b14c2178  MuBangumi-2.2.0-build27-windows-x64.zip
```
