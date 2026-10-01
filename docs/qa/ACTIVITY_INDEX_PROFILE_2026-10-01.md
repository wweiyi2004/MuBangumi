# 追番打卡、目录与主页

- 追番页快捷操作下新增热力图，原继续追列表保留。统计本机新标为“看过”的章节，重复状态不累计，取消扣回；撤销取消时恢复原打卡日期。记录与离线同步意图在同一 SQLite 事务中保存，按账号隔离。旧章节更新时间不是打卡历史，因此不补填启用前的数据。
- 同步库保留版本 3 的队列结构，通过 `IF NOT EXISTS` 增加可选打卡表，不阻断旧客户端读取已有队列。
- 章节展示使用正数 `ep`，缺失时使用正数 `sort`。特别篇、OP、ED 等有类型前缀，未知编号显示类型或占位符，保留原始 API 数值。
- 品牌基色统一为官网 `#F09199`；小文字采用同色系深玫瑰色，实心按钮的文字使用深色。状态、评分等语义颜色保留。
- 二维码使用深梅色、圆点和暖粉边框，不遮挡功能模块。小尺寸使用方形模块和适当纠错密度。导出图片测试覆盖条目、目录、好友和合成房间长链接。
- 发现与个人空间增加番剧单入口：热门/最新、创建/收藏列表、作品分页、详情、推荐语、条目跳转、创建/编辑、收藏、备注/顺序、条目移除及目录删除。共享链接和扫描支持 `/index/{id}`。所有写入继续通过 `CommunityWriteClient`，旧账号响应不更新新账号；创建结果不确定时不自动重发。
- 官网长介绍 `bio` 独立读取并显示在自己的空间与他人主页。签名保留，支持完整富文本介绍；折叠内容不在预览中暴露。

针对性回归使用合成数据，没有向真实账号发送目录或个人资料修改。移动设备扫码、真实账号目录写入和跨设备使用仍需实际验收。

上游依据：[官网配色样式](https://bgm.tv/css/dist/bangumi.min.css)、[目录路由](https://github.com/bangumi/server-private/blob/master/routes/private/routes/index.ts)、[目录收藏](https://github.com/bangumi/server-private/blob/master/routes/private/routes/collection.ts)、[用户资料](https://github.com/bangumi/server-private/blob/master/routes/private/routes/user.ts)。
