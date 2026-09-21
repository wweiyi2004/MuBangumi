# Android 消息验证返回后的恢复与小组权限兼容

用户已安装 Android #3 并重启，网页登录出现头像后自动返回消息页，但仍提示登录；官网已经加入的小组仍提示 `you don't have permission to create posts,join group first`。

## 定位与修复

- 私信页原先仅检查收件箱的 `needAuth`。当发件箱独立失败时，即使验证成功，旧错误也不会触发重置。现在按合并联系人控制器检查两侧状态，恢复后重新同步。
- 网站请求失败原先仅按认证 Cookie 判断归属。同一账号重新验证或刷新浏览器/挑战 Cookie 后，先前请求的错误仍能撤销新的账号绑定。现在用包含验证时间、浏览器身份和 Cookie 快照的摘要识别请求上下文；过期上下文的错误不能撤销新登录。私信 GET 最多用新上下文重读一次，POST 不自动重发，不确定结果要求先确认。
- 页面原生加载状态可能因图片或脚本未完成一直保持 loading，即使登录 DOM 已可交互。现在检查 `document.readyState`，允许 interactive / complete，并继续核对页面 URL、账号导航与前后原生认证 Cookie；loading 和跨页面捕获仍不能建立绑定。Android URL 变化事件同步当前地址。
- 兼容小组成员检查的 `NOT_ALLOWED` + `join group first` 在旧部署中的 HTTP 401 和新版本 HTTP 403；只有明确的这类错误进入已有经典网页提交路径，网站继续检查成员资格、Cookie 和 formhash。普通权限拒绝不进入此路径。
- 消息页显示具体的网页登录状态或同步错误，避免所有失败都只有同一句补充验证提示。

## 证据与验证

- 原生 loading / DOM interactive、发件箱单独失败后的重新验证两项回归在修复前失败，修复后通过。
- 10 项新增请求恢复用例覆盖同 Cookie 重新核验、User-Agent / challenge Cookie 更新、迟到 401 / challenge、GET 单次重读上限、POST 不重发以及小组请求归属。
- 既有账号切换隔离、草稿归属、真正登录失效、真实挑战和一次性验证码提交规则继续通过。
- 全量 Flutter 测试 **1,233 项通过**；`flutter analyze --no-pub lib test` 无问题；架构检查通过。
- 所有私信与发帖回归均使用模拟网络响应，没有向真实好友或小组发布测试内容。没有真实 Android 账号的 HTTP 抓包，本报告确认代码缺陷与回归结果，不将其等同于用户现场已恢复。

## 上游参考

- [旧版 NotAllowedError（HTTP 401）](https://github.com/bangumi/server-private/blob/58542ee46a27ee4753b903635533257124671345/lib/auth/index.ts)
- [上游改为 HTTP 403 的提交](https://github.com/bangumi/server-private/commit/b6fc05f63ba6563be3a1bf8c29036326610e4d25)

## 发布

沿用 `2.3.1+4029` 的独立热更新基线，仅移入上述 Dart 修复。补丁编号与服务端回读结果在发布完成后补充。
