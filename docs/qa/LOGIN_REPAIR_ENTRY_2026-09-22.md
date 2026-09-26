# Windows 登录恢复入口修复

用户提供的诊断中，API 已登录，网站会话从 `available`（3）转为 `expired`（4），之后反复经过 `checking`（2）回到 4。HTTP 200 只说明收到了响应，登录页也会返回 200；这份记录不能证明网站会话有效，也不能确定最初过期的原因。

进一步反馈是“点击补充登录验证也不会打开内置网页”。回归测试复现了旧入口的问题：先进行 HTTP 核验，再为 expired 状态创建隐藏 WebView 清 Cookie，完成以后才推入登录页面。任一步挂起都会让用户停在原页面。

修复后的行为：

- 显式“补充账号验证”立即进入验证页，不再等待独立 HTTP 核验；正在核验时仍可打开。
- expired 状态不清空浏览器当前登录，也不注入已被拒绝的旧 Cookie。通过当前可见网页重新确认账号，仍要求与应用账号一致。
- mismatch 或清理失败仍保留账号隔离；清理移到可见页面内，提供进度、失败说明和重试。
- 读取登录记录超时会显示重试；WebView 初始化超时后释放迟到的实例，重试可以创建新实例。关闭页面会结束等待，避免留下超时定时器。
- 诊断增加 loginOpened、browserStarting、browserReady、browserFailed、browserTimeout 固定事件，不记录 Cookie、URL、账号或网页内容。

验证包括登录入口与既有账号/会话回归，以及本机实际 Windows WebView 的独立冒烟：新建专用浏览器目录，只加载本地 HTML，确认渲染与 JavaScript 返回。测试不读取应用账号，不发送私信或小组内容。

```powershell
. ./tool/toolchain.ps1
Invoke-MuFlutter -Arguments @('test','--no-pub','integration_test/windows_webview_smoke_test.dart','-d','windows')
./tool/verify_all.ps1 -Mode Full
```

真实账号过期后可能仍需在网页完成一次登录。当前修复覆盖恢复入口和浏览器生命周期；不把本地模拟测试或独立浏览器冒烟当作真实账号验收。
