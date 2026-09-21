# 小组发帖及聊天重复验证：第二轮排查

用户确认已安装 Windows #1 / Android #2 并重启，仍出现小组提交失败或重复验证、聊天反复要求账号验证。

## 确认的缺陷

1. `WebsiteIdentityProbe.isChallenge` 原先只要发现 `cf-chl-` 或 `/cdn-cgi/challenge-platform/` 就撤销网站登录。Cloudflare 正常 HTML 响应也可能包含后台 JavaScript Detections，因此登录成功后的私信读取或小组网页表单读取仍会误报挑战。
2. 官方 P1 的发话题成员检查仍以 `isMemberInGroup(group.id, auth.userID)` 调用参数定义为 `(userID, groupID)` 的函数；该路径现在返回 `NOT_ALLOWED` 和 `join group first`，而客户端只兼容旧 `NOT_JOIN_PRIVATE_GROUP_ERROR`。
3. 客户端遇到没有明确错误代码的 401 会刷新授权并重发，可能重用已消费的人机验证令牌；同时漏掉了官方凭据过期代码 `TOKEN_INVALID`。
4. 发话题的授权刷新重试没有再次检查账号上下文；经典网页提交仅凭返回 HTML 中出现 `postTopic` 或任意 `/group/topic/` 链接就报告成功，证据不足。

此处根据代码、官方公开协议与模拟请求复现确认缺陷，没有获取用户的真实 HTTP 抓包，不能将每个现场错误都断言为同一个原因。

## 修复

- 优先使用响应头 `cf-mitigated: challenge` 判断真正的挑战；缺少响应头时检查明确的挑战标题、表单和编排脚本。正常账号导航和后台检测脚本不再单独触发登录撤销。
- 身份核验、私信 GET/POST、小组网页 GET/POST 使用一致的判定。真实挑战（包括 503 挑战页）仍会阻止操作。
- 仅对小组接口的明确成员检查错误进入既有网页登录表单路径，实际提交仍由网站验证 Cookie、formhash、成员资格和权限。普通 `NOT_ALLOWED`、禁言等错误不进入此兼容路径。
- 携带一次性验证码的写请求只在明确的凭据错误时刷新后重试；支持 `TOKEN_INVALID`，未知 401 / CAPTCHA 错误不重放；账号变化则取消重试。
- 去掉不可靠的网页“发帖成功”字符串判断；网络丢失或服务器错误提示先确认结果，避免重复提交。

## 验证

- 修复前新增的 10 项针对性回归全部失败，修复后通过；随后补充真实挑战、普通权限拒绝和不确定提交的反向用例。
- 全量 Flutter 测试 **1,218 项通过**；静态分析无问题；架构边界检查通过。
- 测试中的私信、话题提交均由拦截器替身响应，没有向真实好友发送信息或在真实小组发帖。
- 未自动完成实际 CAPTCHA；客户端仍要求用户完成官方人机验证，并由服务端验证令牌。

## 主要参考

- [Cloudflare JavaScript Detections](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/javascript-detections/)：普通 HTML 响应也可插入 challenge-platform 检测脚本。
- [Cloudflare Challenge 响应识别](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/)：`cf-mitigated` 响应头。
- [Turnstile 服务端验证](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/)：令牌单次使用及有效期。
- [Bangumi P1 小组路由](https://github.com/bangumi/server-private/blob/master/routes/private/routes/group.ts)、[成员检查参数定义](https://github.com/bangumi/server-private/blob/master/lib/group/utils.ts)、[鉴权和验证码中间件顺序](https://github.com/bangumi/server-private/blob/master/routes/hooks/pre-handler.ts)、[凭据错误代码](https://github.com/bangumi/server-private/blob/master/lib/auth/index.ts)。
