# MuBangumi Native Android

> ⚠️ **本模块已冻结**：这是停留在 1.7.0 时代的功能原型，不再随 Flutter 主线更新。代码保留供参考，请勿基于它发布或继续开发；如需原生版本应重新立项。已知未解决问题：Token 明文存储、手写图片加载无磁盘缓存、API 行为与 Flutter 版存在漂移。

MuBangumi 的原生 Android **原型**，使用 Kotlin、Jetpack Compose 和 Material 3。它是独立 Gradle 工程，不依赖 Flutter 运行时，并保留原应用的粉色品牌主题、卡片布局与五栏主导航。

当前 Access Token 以明文写入 `SharedPreferences`，登录方式也只是粘贴 Token。这不是正式发布包：不要把它当作 `com.wweiyi.mubangumi` 的替代品分发，也不要把它附到 Flutter 版的 GitHub Release。对外发布前需要改用 EncryptedSharedPreferences / Android Keystore。

## 已迁移功能

- Bangumi Access Token 登录、登录态恢复与退出
- 同步全类型收藏，按类型、状态与关键词筛选
- 首页收藏统计、继续追、单击“下一集看过”
- 本地新番表与进行中动画列表
- 季度浏览、全类型条目搜索与条目详情
- 修改收藏状态、查看评分、排名、简介与标签
- 原生浏览小组/条目话题列表
- 原生话题详情、好友列表与电波提醒
- 用户资料、收藏统计、深色/浅色主题
- 无 Token 的演示模式

除 Access Token 获取需要打开 Bangumi 网页外，社区详情、好友和电波提醒都在应用内完成。Flutter 版依赖网站 Cookie 或第三方服务的私信、二维码、评分历史、海报导出和热更新能力没有混入原生核心，后续可以在此模块上继续逐项迁移。

## 构建

环境要求：JDK 17 或更高版本、Android SDK 36。

在仓库根目录执行：

```powershell
$env:ANDROID_HOME = 'C:\path\to\Android\sdk'
.\android\gradlew.bat -p native-android :app:assembleDebug
```

Debug APK 输出到：

```text
native-android/app/build/outputs/apk/debug/app-debug.apk
```

也可以用 Android Studio 直接打开 `native-android/`。如果没有设置 `ANDROID_HOME`，请在该目录创建不提交的 `local.properties`：

```properties
sdk.dir=C:\\path\\to\\Android\\sdk
```

## 代码结构

```text
native-android/app/src/main/java/com/wweiyi/mubangumi/nativeapp/
├─ MainActivity.kt            # 原生入口
├─ MuBangumiApp.kt            # 登录、导航与根页面
├─ Screens.kt                 # 五个主页面、详情与新番表
├─ MuBangumiViewModel.kt      # 会话和页面状态
├─ BangumiApi.kt              # OpenAPI/P1 网络层
├─ Models.kt                  # 条目、收藏、用户与话题模型
├─ RemoteImage.kt             # 轻量图片加载与内存缓存
└─ AppTheme.kt                # 与 Flutter 版一致的主题色
```
