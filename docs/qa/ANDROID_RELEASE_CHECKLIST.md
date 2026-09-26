# Android 发布前设备验收

自动化与人工验收分别记录。CI 的 `Android device smoke` 手动工作流验证真实原生插件；官方登录、人机验证与服务器权限必须在受控测试账号/小组中由验收人员完成，不能用模拟响应替代。

## 自动化平台冒烟

在专用模拟器或备用测试设备运行。不要为测试卸载日常使用的正式版；测试包与正式包签名可能不同。

```powershell
./tool/setup_workspace.ps1 -Flutter
# 查看可用设备后，把 ID 传给完整验证。
./tool/verify_all.ps1 -Mode Full -DeviceId emulator-5554
```

`integration_test/platform_smoke_test.dart` 使用单独入口，不启动主应用，不加载真实凭据，不发送远程请求。它验证安全存储的唯一临时键、内存 SQLite 和本地 WebView HTML/JavaScript 桥接。不会写入 bgm.tv Cookie。

Windows 本机使用 `./tool/verify_all.ps1 -Mode Full -WindowsSmoke`。安全存储/SQLite 共用上述独立入口，移动 WebView 用例在 Windows 明确跳过；Windows WebView 由 `integration_test/windows_webview_smoke_test.dart` 在独立临时浏览器目录中验证。自动化不会验证真实登录、系统文件对话框、提醒送达或更新安装。

构建、插件冒烟与人工业务验收必须分开记录。传入 `-DeviceId` 也不会自动生成或完成真实账号验收记录。

## 真实账号验收

复制 `tool/qa/acceptance.example.json` 到被忽略的 `.dart_tool/acceptance-android.json`。填写当前源码指纹、安装基线版本、完成时间和证据引用；只将实际通过的项目改为 `passed`。Windows 发布使用同一格式，platform 改为 windows。

```powershell
python tool/release_provenance.py identity --root .
```

| 字段 | 操作与通过条件 |
| --- | --- |
| oauth_login | 完成官方 OAuth；核对应用账号；打开私信和小组，无异常重复验证 |
| saved_session | 完全退出再启动；已有有效会话能恢复；离线时仍保留账号和缓存 |
| session_expiry | 让测试会话失效；显示补充验证入口，正常 API 登录不被一并清除 |
| website_challenge | 在出现真实验证的页面由人完成；不会提前自动返回；回到业务后可重试 |
| network_recovery | 断网或切换网络后恢复；刷新可重新工作，草稿和待处理任务保留 |
| foreground_resume | 输入中退后台再回来；内容保留，状态不被旧请求覆盖 |
| account_switch | 旧请求在切换后完成；不得使用新账号重放旧写操作或展示旧私信 |
| pm_delivery | 向专用测试收件人发信并确认回执；未知结果不自动重发；重新进入可核对 |
| group_write | 在专用测试小组发帖/回复；权限失败可解释；验证可就地恢复且输入保留 |

设备证据记录安装版本、补丁号、OS/WebView 主要版本、场景结果即可，不放入密码、Token、Cookie、私信正文或真实联系人信息。未出现或未测试的场景保持 pending，并说明原因，不自动填为通过。

## 发布记录

先从审阅并提交的源码运行 `tool/verify_all.ps1 -Mode Full`，再将其 `results.json` 与人工验收 JSON 交给发布脚本。源码内容、平台、版本或必需检查不匹配时，上传会在构建前被拒绝。

```powershell
./tool/build_release.ps1 -Target apk -Shorebird `
  -VerificationReport .dart_tool/verification/<run>/results.json `
  -AcceptanceReport .dart_tool/acceptance-android.json
```

补丁还需要明确 `-Patch -ReleaseVersion 版本+构建号`。成功后核对 Shorebird 服务端返回的补丁编号/ID/通道，再执行 `patch-receipt` 命令补全本机来源记录，并用 `--artifact` 指定实际编译出的 AAB 或 Windows `app.so` 以记录哈希。未补全的记录保持 awaiting-patch-receipt，不自动声称远端版本已核对。补丁实际引擎来自服务端安装基线，不能把本地 SDK 元数据当作引擎一致性证明。

自动验证和人工验收记录都必须在最近 7 天内；源码发生变化需重新验证。人工记录不含真实账号信息，只有通过状态与证据引用。
