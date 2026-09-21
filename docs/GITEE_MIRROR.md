# Gitee 镜像与断点续传

GitHub 是主仓库。Gitee 同步 `main` 和版本标签，并保存同一次构建的 APK / Windows ZIP。代码同步不会复制 GitHub Release 附件，附件由独立发布步骤下载、校验和上传。

本项目默认 Gitee 仓库为 `wweiyi/mu-bangumi`（https://gitee.com/wweiyi/mu-bangumi）。镜像尚未完成或不可用时，自动回退到 GitHub。可通过构建参数覆盖；显式传空 `--dart-define=GITEE_REPOSITORY=` 可禁用应用镜像。官网使用 GitHub Actions 仓库变量配置。

## 首次启用

1. 在 Gitee 创建公开空仓库（不初始化 README），或导入本项目 GitHub 仓库。确认仓库可公开访问。
2. 在 GitHub 仓库 **Settings → Secrets and variables → Actions** 设置：
   - Variable `GITEE_REPOSITORY`：`你的用户名/MuBangumi`，不要加域名或 `.git`。
   - Variable `GITEE_USERNAME`：有权推送镜像仓库的 Gitee 登录用户名；组织仓库也填写实际登录用户。
   - Secret `GITEE_TOKEN`：具有对应仓库推送及发行版管理权限的 Gitee 令牌。不要提交到代码或编译进客户端。
3. 将本次代码和工作流推送到 GitHub 后，手动运行 **Sync code and releases to Gitee**，填写已有的正式版标签。未填写标签时只同步代码。
4. 查看工作流日志：安装包上传后必须通过免登录完整下载及 SHA-256 校验。只有全部成功才写入可供应用读取的更新清单。日志同时报告实际 `Range` 支持情况。
5. 构建带镜像配置的**完整应用版本**，例如：

   ```powershell
   ./tool/build_release.ps1 -Target apk -GiteeRepository '你的用户名/MuBangumi'
   ./tool/build_release.ps1 -Target windows -GiteeRepository '你的用户名/MuBangumi'
   ```

   也可设置构建环境变量 `GITEE_REPOSITORY`，或直接传 Flutter 参数 `--dart-define=GITEE_REPOSITORY=你的用户名/MuBangumi`。GitHub Actions 的仓库变量不会自动传入你本机的构建环境。

6. 重新运行官网 Pages 工作流，即可显示“国内下载（Gitee）”。本地构建官网使用 `NEXT_PUBLIC_GITEE_REPOSITORY` 环境变量。

## 后续发布

- `main` 或 `v*` 标签推送时同步代码；发布或编辑 GitHub 正式 Release 时同步安装包。
- 推荐先上传所有安装包，再发布 GitHub Draft Release，防止镜像只看到部分附件。若发布后追加附件，手动以该标签重跑镜像工作流。
- 工作流只推送主分支和标签，不强推、不删除 Gitee 上的分支；Gitee 有分叉提交时会失败，需要先处理冲突。
- 每个版本只构建一次，两边发布同一文件。不能在两个平台分别构建后使用相同版本号。
- 不自动覆盖同名但校验不同的附件；遇到冲突应发布新版本，避免已下载的字节失效。
- 上传失败或配额不足时工作流报错，不将未完成的镜像公布给更新器。单附件大小、总配额和公开下载能力以实际 Gitee 账号为准。
- 当前 `v2.3.1+4029` 通用 APK 为 111,829,288 字节。如果账号限制低于此大小，需发布按 ABI 拆分的 APK（普通 `build_release.ps1 -Target apk` 已支持），或换用可容纳该文件的下载服务；不要把分卷压缩文件直接当作可安装 APK。Shorebird 的完整 APK 构建仍需单独检查大小。
- 镜像工作流未启用或仓库变量为空时，会跳过同步，不影响原 GitHub 发布。

本地发布工具（需要 Python 3.10+）：

Windows 可直接运行交互入口，令牌只在本机终端输入，不显示、不写入文件，退出后恢复原环境变量：

```powershell
./tool/publish_gitee.ps1 -Tag 'v2.3.1+4029'
```

如果 GitHub Actions 中的 Gitee API 持续返回非 JSON 的 403 页面，而本机访问正常，可以使用上述入口切换发布网络。代码推送成功不等于附件已发布；必须等待脚本报告公开下载与校验通过。

```powershell
python -m pip install -r tool/requirements-mirror.txt
# 仅下载并校验 GitHub 原始安装包，不写入 Gitee：
python tool/mirror_release.py --repository '你的用户名/MuBangumi' --tag 'v2.3.1+4029' --dry-run
# 实际发布：在安全的本地环境中提供 GITEE_TOKEN；GH_TOKEN 是可选的 GitHub API 凭据。
python tool/mirror_release.py --repository '你的用户名/MuBangumi' --tag 'v2.3.1+4029'
```

## 应用中的行为

- 检查更新同时查询两个平台，采用较新的版本；任一平台不可用时使用另一个。两者都失败时提示检查失败，不误报“已经是最新版”。
- 下载面板记住“自动选择 / 国内源（Gitee）/ GitHub”。只有当前安装包存在可信镜像时才显示国内选项；没有镜像时仍可使用 GitHub。
- 自动模式先尝试国内源，失败重试后切换 GitHub；手动选择时只使用指定来源。
- 暂停、网络失败、退出应用后保留已下载内容。再次打开该版本的更新面板会恢复进度，点击“继续下载”请求剩余字节。
- “取消并删除”清除当前安装包及其下载进度。关闭面板不停止下载。
- 服务器返回有效 `206 Content-Range` 时追加；忽略 `Range` 并返回 `200` 时先清空旧内容再下载。范围异常和校验失败会丢弃损坏内容后重试。
- 自动模式中，如果国内源忽略 `Range`，先保留已有字节并切换 GitHub 续传；仅当选定的来源或最后的备用来源也不支持时才从头下载。2026-09-21 的公开附件探测中，GitHub 本项目安装包支持 Range，而抽样 Gitee 附件未返回有效 Range 响应；不能据此承诺所有 Gitee 附件都支持续传，具体以发布日志和实际请求为准。
- 以 SHA-256 和文件名区分进度；只有文件大小和 SHA-256 一致时才允许两种来源共享进度。安装前再次校验完整文件。
- 完整安装包保存在应用私有持久目录，不随普通临时缓存清理。卸载应用或清除应用数据仍会删除它们。

## Android 发布要求

本次变更将安装包从 cache 目录移到 files 目录，并同步修改 Android `FileProvider` 和原生安装入口。因此首次上线需要完整 APK 更新，**不能仅用 Shorebird Dart 补丁发布到旧原生基线**。已有旧客户端可以从 GitHub 获取新 APK；安装新 APK 后才使用新的续传功能。

## 验证

```powershell
flutter test --no-pub test/update_resume_test.dart test/release_catalog_test.dart test/update_experience_test.dart test/github_release_test.dart test/app_update_service_test.dart
python -m unittest discover -s tool/tests -p 'mirror_release_test.py'
```

尚未创建镜像仓库时，可以完成本地测试和 GitHub 原包的 dry run，但无法宣称本项目的 Gitee 上传、免登录下载和国内线路已验收。首次部署应在实际仓库上完成上述工作流，再用应用测试暂停续传及国内源下载。
