# 双源更新与断点续传验证（2026-09-21）

## 已完成

- 更新器支持暂停、恢复、进程重启后读取进度、网络重试、来源切换、完整文件校验与取消删除。
- GitHub / Gitee 双源版本查询，比较版本及构建号；相同版本仅合并文件名、大小、SHA-256 一致的镜像。
- 自动模式遇到 Gitee 忽略 Range 时保留字节，切换 GitHub 续传；手动来源或最后的来源不支持时安全重下。
- Gitee 主分支及标签同步工作流；附件复制、公开下载校验、完成后发布清单；本地 dry run 支持。
- 可配置的官网国内下载入口和构建参数。

## 验证结果

- 首轮六个更新测试文件合计 53 项通过；增加“不支持 Range 的镜像保留前缀并切换 GitHub”回归后，续传及清单两组 20 项通过。合计覆盖 54 项更新测试。
- Python 发布行为测试 7 项通过：包括上传后校验失败不公布清单、已存在附件校验后复用、dry run 无远程写入。
- PowerShell 发布构建检查 9 项通过，包含镜像编译参数传递和无效仓库配置拒绝。
- 针对 `lib/core/update`、更新对话框及新测试的 Flutter 静态分析通过。
- 架构边界检查通过（251 个 Dart 文件）。
- `flutter build apk --debug --no-pub` 成功生成调试 APK；未进行设备安装验证或生产发布。
- 官网 ESLint 通过；使用 CI 同版本 Node 22 的 `npm run test:pages` 构建与静态导出测试通过，导出 HTML 含配置的 Gitee 链接。
- 真实 dry run 下载 `v2.3.1+4029` Android APK（111,829,288 字节）和 Windows ZIP（21,158,309 字节），均与 GitHub SHA-256 一致，未写入 Gitee。

## 环境与部署限制

- 初次全项目 Flutter 分析进程发生 Dart VM 崩溃，后续针对本次改动的分析通过；没有将首次全项目分析记作通过。
- 本机 Node 24 首次官网构建在退出阶段发生 libuv 崩溃；使用 Node 22 后完整构建通过，没有改动项目构建实现来掩盖错误。
- 实测本项目 GitHub Windows 包支持 Range；抽样 Gitee 官方 CLI 二进制附件及校验文本未返回有效 Range 响应。这不代表所有 Gitee 仓库的行为相同，发布工具会逐文件探测并记录。
- 用户尚未创建 Gitee 仓库，故没有设置真实 Gitee 地址、配置远端 Secret、上传附件、启用线上镜像或验证实际国内线路速度。
- Android 原生安装目录有变更，需发布完整 APK，不能仅给旧基线推 Dart 补丁。
- 启用步骤与当前 APK 配额注意事项见 [Gitee 镜像配置](../GITEE_MIRROR.md)。

## 后续配置与首次上线结果

- 已绑定公开仓库 `wweiyi/mu-bangumi`，GitHub 仓库变量与用户提供的 Secret 已确认存在。
- 主分支、全部版本标签已成功同步至 Gitee；官网部署成功；首个功能提交的完整 Flutter CI 通过，后续已完成的 CI 也通过。
- 更新相关测试完整重跑 54 项通过；发布脚本随着诊断和重试改进增加至 9 项测试，通过。
- Gitee `v2.3.1+4029` 发行版已创建为预览状态，但附件尚未发布成功，未公布应用更新清单。
- GitHub Actions 多次收到 Gitee 非 JSON HTTP 403，匿名元数据读取也受影响；本机读取相同公开仓库 API 返回 200。另一次发布运行耗时约 9 分钟仍无附件，已取消。
- 已增加受限重试、请求及上传超时、上传进度日志，并提供本机交互发布入口 `tool/publish_gitee.ps1`。GitHub Secret 不能读回到本机，使用本机入口需用户在终端输入 Gitee 令牌。不能把当前状态描述成安装包国内镜像已验收。

## 100 MB 限制处理与镜像发布完成（06:50 UTC）

- 用户在本机成功上传并校验 Windows ZIP；Android 通用 APK 被 Gitee 明确以 100 MB 单附件限制拒绝。
- 已增加上传前大小筛选。超过 100,000,000 字节的文件保持 GitHub 下载，不下载、不上传、不阻止其他平台发布；所有文件均超限时直接报错且不写远端。
- 更新清单允许同时包含国内镜像文件和明确的 GitHub-only 文件，至少需要一个完成校验的国内文件；错误镜像 URL 仍被拒绝。
- Python 测试 11 项、相关 Flutter 测试 27 项及对应静态分析通过。Windows PowerShell 5.1 真实 dry run 确认只校验 Windows 原包，跳过超限 APK。
- GitHub Actions 运行 https://github.com/wweiyi2004/MuBangumi/actions/runs/35570143439 成功，复用并校验已有 Windows 附件，正式发布 `v2.3.1+4029` 镜像清单。
- 公开 API 核对：发行版 `prerelease=false`；Windows 21,158,309 字节，具有 Gitee 镜像；Android 111,829,288 字节，仅保留原 GitHub URL。Windows 附件不支持 Range，自动续传按设计切换 GitHub。
- Windows 国内下载已验收；Android 国内直装仍需另外提供经过验证的小体积 APK，当前不可宣称 Android 已有国内镜像。
