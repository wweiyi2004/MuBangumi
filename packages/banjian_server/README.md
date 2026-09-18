# 番键会服务

这是 MuBangumi 内置活动服务的同一份 Dart 实现，可以单独运行在 Windows / Linux 服务器上。管理端、浏览器参与端随服务打包；原生客户端通过相同 API 和 WebSocket 协议参与。**不含音频或视频分发。**

## 本地开发

在本目录运行，需 Dart 3.12 或更新版本：

```powershell
dart pub get
$env:BANJIAN_ADMIN_PASSWORD = '请替换为至少12位的管理密码'
dart run bin/server.dart
```

打开 `http://localhost:43928/admin`，输入该密码，创建活动、添加番剧、开始第一轮。其他设备使用电脑 Wi-Fi / 热点网卡对应地址，不能使用 `localhost`。参与二维码和管理密码分开分享。

从本机管理页分享时，服务会优先选择热点 / Wi-Fi / 有线网络地址；远程管理页保留其已连接成功的网卡地址。二维码同时携带最多 7 个同端口私有 IPv4 备选地址供 MuBangumi 自动探测，浏览器仍从主地址进入。`/api/invitation` 返回一致的链接与二维码，`/api/locate` 使用随机挑战响应核对房间；旧格式参与链接仍可供新版服务使用。只有回环监听时会明确标记仅本机。

原生入口：MuBangumi → 我的 → 设置 → 实验性功能 → 番剧鉴赏 → 连接服务器。局域网可以填写 HTTP IP 地址，公网填写 HTTPS 域名根地址，不附加 `/admin`。

连接后点击「进入管理」使用软件内的原生管理台；菜单中的「浏览器管理入口」可打开同一服务的网页台。两端均接收 WebSocket 状态；首次载入与主动下拉使用同一套迷你放映窗字符提示，实时推送不反复播放加载动画。

| 环境变量 | 默认值 / 用途 |
| --- | --- |
| `BANJIAN_ADMIN_PASSWORD` | 必填，至少 12 位；不要提交到版本库 |
| `BANJIAN_BIND` | `0.0.0.0` |
| `PORT` | `43928` |
| `BANJIAN_DATA` | `./data`，数据库与已缓存封面 |
| `BANJIAN_WEB` | `./web`，三个随包静态文件 |
| `BANJIAN_PUBLIC_ORIGIN` | 公网反代时填完整来源，如 `https://banjian.example.com`；用于来源校验及二维码 |

## 跨网络部署

提供 `Dockerfile`、`compose.example.yaml` 和 `Caddyfile.example`。需要一台服务器、可用域名及 80/443 端口：

1. 复制 `Caddyfile.example` 为 `Caddyfile`，填写自己的域名。
2. 设置 `BANJIAN_DOMAIN` 和强管理密码 `BANJIAN_ADMIN_PASSWORD`。
3. 执行 `docker compose -f compose.example.yaml up -d --build`。
4. 访问域名的 `/admin`；在 MuBangumi 中连接相同 HTTPS 根地址。

Compose 只对公网暴露 Caddy 的 80/443，活动服务端口留在容器网络。Caddy 同时代理 WebSocket。数据卷 `room-data` 保存记录；停止或重建容器不应删除此卷。绑定自定义宿主目录时，要让容器用户 UID 10001 有写入权限。

**本轮未连接用户的公网服务器，也未配置真实域名证书。Docker 模板尚未实机部署验证：本机 Docker Linux 引擎未运行。** Windows 独立 CLI 的编译及 HTTP/WebSocket 服务已本地验证。

## 独立可执行文件

```text
dart build cli --target bin/server.dart -o build
```

交付整个 `build/bundle`，保留 `bin`、`lib` 相对位置，并把 `web/` 复制到 bundle 根目录。在 bundle 根目录设置上述环境变量后运行 `bin/server.exe`（Linux 对应 `bin/server`）。不能只复制一个 exe，SQLite 动态库也需要随包携带。

## 数据与权限

- SQLite WAL + FULL 同步事务。操作回执与活动修改一起落盘，重复操作 ID 不会重复计票或生成短评。
- 当前服务同时允许一场未结束活动，最多 100 轮、500 个参与身份，每轮最多 5,000 条短评。目标使用规模为 50 个在线参与端。
- 管理会话 12 小时过期，支持退出撤销、失败限频和来源校验；管理网页使用独立 Bearer 会话。
- 参与邀请包含随机秘密；参与者自己的随机凭据用于恢复身份、修改评分。管理密码不进入参与二维码。
- 服务端将原始数据投影成相应角色的视图；未公布统计不传给参与者，其他人的未公开短评同样不传。
- 普通管理视图仅给出入场姓名和当前轮次是否提交。JSON/CSV 导出只包含汇总、匿名短评和活动信息，不提供姓名—评分对照。
- 内部数据库仍包含身份与评分关联，以便修改评分与防重复。这不是对数据库持有者的密码学匿名。网页姓名为自填显示名，也不保证一人一票。
- 评论作为纯文本显示；CSV 对公式前缀转义；静态资源不依赖 CDN。服务不读取 MuBangumi 的账号 Token、Cookie、私信或其他文件。
- 选中条目的封面由后台缓存，支持收藏导入提供的官方图片 URL；历史快照缺少 URL 时通过条目 ID 补齐。服务启动和当前活动的定时重试可恢复失败任务，管理页也可手动「补全封面」。图片更新不改变活动规则版本、评分或评论。
- 本机活动服务数据库单独位于应用支持目录 `banjian/banjian.sqlite`；独立服务位于 `BANJIAN_DATA`。需要迁移时停止服务后复制完整数据目录，不要只复制运行中的主数据库文件。

## 验证

```text
dart analyze
dart test
dart run tool/load_check.dart 120
```

`load_check.dart` 使用临时数据库和回环地址，可传入秒数；默认两分钟。短时本机压测不代表真实 Wi-Fi、热点设备上限或 Android 锁屏保活结果。完整验证记录见仓库 `docs/qa/banjian-implementation/README.md`。
