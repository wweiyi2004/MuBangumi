import type { ReactNode } from "react";
import Image from "next/image";
import { ProductDemo } from "./ProductDemo";
import { currentRelease } from "./release";

export const dynamic = "force-static";

const githubUrl = "https://github.com/wweiyi2004/MuBangumi";
const releasesUrl = `${githubUrl}/releases/latest`;
const giteeRepository = process.env.NEXT_PUBLIC_GITEE_REPOSITORY ?? "";
const giteeReleasesUrl = /^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+$/.test(giteeRepository) &&
  !giteeRepository.split("/").some((part) => part === "." || part === "..")
  ? `https://gitee.com/${giteeRepository}/releases` : null;
const faviconUrl = `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/favicon.svg`;

const features = [
  {
    icon: "check",
    title: "追番进度，清楚一点",
    description:
      "首页点格子、一键标记下一集，用打卡热力图看看自己的节奏；网络恢复后继续同步。",
  },
  {
    icon: "sparkles",
    title: "发现真正想看的",
    description:
      "按季度、口碑趋势和个人收藏口味探索作品，让下一部不再靠反复翻榜单。",
  },
  {
    icon: "users",
    title: "社区就在手边",
    description:
      "时间线、超展开、小组话题、好友和站内短信，都用更适合移动端的方式呈现。",
  },
  {
    icon: "calendar",
    title: "自己的新番表",
    description:
      "按周几安排本季追番，和官方每日放送互不干扰，还能导出成海报分享。",
  },
  {
    icon: "chart",
    title: "看懂评分变化",
    description:
      "对比多部作品的历史评分，也能查看收藏统计和好友口味，不只盯着一个数字。",
  },
  {
    icon: "shield",
    title: "数据由你掌握",
    description:
      "本地备注、好友分组与收藏快照留在设备上；配置迁移有密码保护，登录凭据单独存储。",
  },
] as const;

const platforms = [
  { label: "Android", note: "通用 APK · 手机与平板", icon: "android", available: true, href: currentRelease.assets.android },
  { label: "Windows", note: "x64 便携 ZIP · 解压运行", icon: "windows", available: true, href: currentRelease.assets.windows },
  { label: "iOS", note: "本版未提供安装包", icon: "apple", available: false, href: null },
] as const;

const updates = [
  { icon: "calendar", title: "把每一次看过，留在日历里", text: "章节打卡热力图记录启用后的观看操作，取消与撤销也会同步调整记录。" },
  { icon: "chart", title: "一起挑选，也一起比较", text: "整理与分享番剧单，对比多部作品的评分历史，查看完整制作人员与个人介绍。" },
  { icon: "sparkles", title: "外观，按自己的喜好来", text: "自定义配色、按需下载或导入字体、统一的圆角菜单，让自己的空间更舒服。" },
  { icon: "shield", title: "常用功能，更轻一些", text: "图片按展示尺寸解码，临时缓存有容量限制；隐藏页面暂停动画，保留页面状态。" },
] as const;

const questions = [
  { title: "第一次安装，选哪一个？", answer: "Android 下载通用 APK，按系统提示确认安装。Windows 下载 x64 ZIP，解压到新的空目录后运行 mubangumi.exe。本版没有 iOS 安装包，也没有 TestFlight 邀请入口。" },
  { title: "已有旧版，怎样升级？", answer: "Android 2.4.2 沿用上一版签名，构建号升至 4032，可尝试覆盖安装；请先备份重要的本地设置。Windows 请使用新的空目录，不要覆盖混有旧程序数据的目录。实际设备的覆盖安装与通知送达仍需验收。" },
  { title: "哪些内容能同步，哪些留在设备上？", answer: "收藏与章节进度通过 Bangumi 账号同步。本地备注、好友分组、外观设置和草稿有各自的存储范围；配置迁移不包含登录凭据、网页登录会话或待同步写队列。个人介绍和部分社区操作可能需要补充网页登录。" },
  { title: "网页演示会修改我的 Bangumi 账号吗？", answer: "不会。演示只使用示例数据，进度、筛选和贴贴只保留在当前页面，刷新即可重置；网页不会连接或修改真实的 Bangumi 账号。它是交互示意，不是软件截图，也不是实时评分。" },
  { title: "GitHub 下载不顺畅，怎么办？", answer: "可尝试下载区的 Gitee 镜像，但镜像同步可能晚于 GitHub。请核对版本与文件名；当前版本的来源记录、检查结果和 SHA-256 校验和都在 GitHub 发行页中。" },
  { title: "本版有热补丁吗？遇到问题在哪里反馈？", answer: "2.4.2 提供 Android 和 Windows 整包更新，不提供本版 Shorebird 热补丁。可通过 GitHub Issues 反馈，附上系统、软件版本与复现步骤；请勿公开 Token、Cookie、私信内容或完整个人数据库。" },
];

function ArrowIcon() {
  return (
    <svg viewBox="0 0 20 20" aria-hidden="true">
      <path d="M4 10h12m-5-5 5 5-5 5" />
    </svg>
  );
}

function GithubIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.87c-2.78.6-3.37-1.18-3.37-1.18-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.9 1.53 2.35 1.09 2.92.83.09-.65.35-1.09.64-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02A9.6 9.6 0 0 1 12 6.82c.85 0 1.69.11 2.48.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.86v2.76c0 .27.18.58.69.48A10 10 0 0 0 12 2Z" />
    </svg>
  );
}

function FeatureIcon({ name }: { name: string }) {
  const paths: Record<string, ReactNode> = {
    check: (
      <>
        <path d="M12 3.2a8.8 8.8 0 1 0 8.8 8.8A8.8 8.8 0 0 0 12 3.2Z" />
        <path d="m8 12.1 2.5 2.5 5.6-5.7" />
      </>
    ),
    sparkles: (
      <>
        <path d="m12 3 1.2 3.8A5.2 5.2 0 0 0 16.6 10l3.9 1.2-3.9 1.2a5.2 5.2 0 0 0-3.4 3.3L12 19.6l-1.2-3.9a5.2 5.2 0 0 0-3.4-3.3l-3.9-1.2L7.4 10a5.2 5.2 0 0 0 3.4-3.2L12 3Z" />
        <path d="m18.5 3.5.4 1.1 1.1.4-1.1.4-.4 1.1-.4-1.1-1.1-.4 1.1-.4.4-1.1Z" />
      </>
    ),
    users: (
      <>
        <path d="M9.3 11.1a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z" />
        <path d="M3.6 20v-1.8a5.7 5.7 0 0 1 11.4 0V20M16 5.2a3.4 3.4 0 0 1 0 6.5M17.1 14a5 5 0 0 1 3.3 4.7V20" />
      </>
    ),
    calendar: (
      <>
        <rect x="3.5" y="5" width="17" height="15" rx="2.5" />
        <path d="M7.5 3v4M16.5 3v4M3.5 9.2h17M8 13h.01M12 13h.01M16 13h.01M8 16.5h.01M12 16.5h.01" />
      </>
    ),
    chart: (
      <>
        <path d="M4 20V5M4 20h16" />
        <path d="m7 15 3.1-3.5 3 2 4.4-6" />
        <circle cx="17.5" cy="7.5" r="1" />
      </>
    ),
    shield: (
      <>
        <path d="M12 3 5 6v5.4c0 4.5 2.8 7.6 7 9.6 4.2-2 7-5.1 7-9.6V6l-7-3Z" />
        <path d="m8.8 12 2.1 2.1 4.4-4.5" />
      </>
    ),
  };

  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      {paths[name]}
    </svg>
  );
}

function PlatformIcon({ name }: { name: string }) {
  if (name === "android") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="m7 6-1.3-2M17 6l1.3-2M5.2 10h13.6v8.2a1.8 1.8 0 0 1-1.8 1.8H7a1.8 1.8 0 0 1-1.8-1.8V10ZM8 10V7.8A3.8 3.8 0 0 1 11.8 4h.4A3.8 3.8 0 0 1 16 7.8V10M9 7h.01M15 7h.01M2.8 10.5v6M21.2 10.5v6M8 20v2M16 20v2" />
      </svg>
    );
  }
  if (name === "apple") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M16.7 12.8c0-2.4 2-3.6 2.1-3.7a4.5 4.5 0 0 0-3.5-1.9c-1.5-.2-2.9.9-3.7.9-.8 0-2-1-3.3-.9a4.9 4.9 0 0 0-4.1 2.5c-1.8 3.1-.5 7.6 1.2 10.1.9 1.2 1.9 2.5 3.2 2.4 1.3-.1 1.8-.8 3.4-.8s2 .8 3.4.8 2.3-1.2 3.1-2.4c1-1.4 1.4-2.8 1.4-2.9-.1 0-3.2-1.2-3.2-4.1ZM14.3 5.6a4.5 4.5 0 0 0 1-3.3 4.6 4.6 0 0 0-3 1.6 4.2 4.2 0 0 0-1.1 3.2 3.8 3.8 0 0 0 3.1-1.5Z" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M3 5.2 10.6 4v7.3H3V5.2ZM12 3.8 21 2.5v8.8h-9V3.8ZM3 12.7h7.6V20L3 18.8v-6.1ZM12 12.7h9v8.8l-9-1.3v-7.5Z" />
    </svg>
  );
}

export default function Home() {
  return (
    <main id="main-content">
      <a className="skip-link" href="#top">跳到主要内容</a>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="MuBangumi 首页">
          <Image src={faviconUrl} alt="" width="40" height="40" priority />
          <span>MuBangumi</span>
        </a>
        <nav aria-label="主导航">
          <a href="#features">功能</a>
          <a href="#updates">更新</a>
          <a href="#platforms">下载</a>
          <a href="#faq">帮助</a>
          <a href="#opensource">开源</a>
          <a href="#references">致谢</a>
        </nav>
        <a className="header-github" href={githubUrl} target="_blank" rel="noreferrer">
          <GithubIcon />
          GitHub
        </a>
      </header>

      <section className="hero" id="top" tabIndex={-1}>
        <div className="hero-glow hero-glow-one" />
        <div className="hero-glow hero-glow-two" />
        <div className="hero-copy">
          <div className="eyebrow"><span /> 第三方 Bangumi 客户端</div>
          <a className="release-pill" href="#updates"><span>NEW</span> {currentRelease.version} 已发布 <ArrowIcon /></a>
          <h1>
            追番这件事，
            <em>简单又好看。</em>
          </h1>
          <p className="hero-description">
            把收藏、进度、发现与社区收进一个舒服的客户端。
            在 Android 和 Windows 上，认真记录每一部喜欢。
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href="#platforms">
              获取 MuBangumi <ArrowIcon />
            </a>
            <a className="button button-secondary" href={githubUrl} target="_blank" rel="noreferrer">
              <GithubIcon /> 查看源码
            </a>
          </div>
          <div className="hero-meta" aria-label="项目特点">
            <span><i>✓</i> 开源免费</span>
            <span><i>✓</i> 多端适配</span>
            <span><i>✓</i> 深浅主题</span>
          </div>
        </div>

        <ProductDemo />
      </section>

      <section className="trust-strip" aria-label="支持平台">
        <span>一个账号，进度处处同步</span>
        <div />
        <b>Android</b><i>·</i><b>Windows</b><i>·</i><span>iOS 暂无安装包</span>
      </section>

      <section className="section updates-section" id="updates" aria-labelledby="updates-title">
        <div className="updates-heading">
          <div><span className="section-kicker">这次的新变化</span><h2 id="updates-title">你的习惯，多一点自己的样子。</h2></div>
          <a className="text-link" href={currentRelease.url} target="_blank" rel="noreferrer">2.4.2 更新说明 <ArrowIcon /></a>
        </div>
        <div className="update-grid">
          {updates.map((update) => <article className="update-card" key={update.title}><FeatureIcon name={update.icon} /><h3>{update.title}</h3><p>{update.text}</p></article>)}
        </div>
      </section>

      <section className="section features-section" id="features">
        <div className="section-heading">
          <span className="section-kicker">不只是一张番表</span>
          <h2>从“想看”到“看完”，<br />每一步都更顺手。</h2>
          <p>围绕真实的追番习惯设计，不把常用操作藏进层层菜单。</p>
        </div>
        <div className="feature-grid">
          {features.map((feature, index) => (
            <article className="feature-card" key={feature.title}>
              <div className={`feature-icon feature-icon-${index + 1}`}>
                <FeatureIcon name={feature.icon} />
              </div>
              <h3>{feature.title}</h3>
              <p>{feature.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="insight-section">
        <div className="insight-visual">
          <div className="insight-card insight-main">
            <div className="insight-head"><span>评分趋势</span><b>近 30 天</b></div>
            <div className="score-line"><strong>8.6</strong><span>+0.4</span></div>
            <div className="chart" aria-hidden="true">
              <svg viewBox="0 0 460 150" preserveAspectRatio="none">
                <defs>
                  <linearGradient id="chartFill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" stopColor="#a84f5a" stopOpacity=".28" />
                    <stop offset="1" stopColor="#a84f5a" stopOpacity="0" />
                  </linearGradient>
                </defs>
                <path className="chart-fill" d="M0 124 C55 118 74 96 116 103 S181 79 225 88 S292 54 330 63 S390 31 460 21 L460 150 L0 150Z" />
                <path className="chart-line" d="M0 124 C55 118 74 96 116 103 S181 79 225 88 S292 54 330 63 S390 31 460 21" />
              </svg>
            </div>
            <div className="chart-labels"><span>7/01</span><span>7/10</span><span>7/20</span><span>今天</span></div>
          </div>
          <div className="insight-card taste-card"><small>与好友的共同收藏</small><b>47 <span>部</span></b><div className="avatar-stack"><i>A</i><i>B</i><i>C</i><em>+8</em></div></div>
          <div className="insight-card review-card"><span>收藏回顾 · 示例</span><b>今年完成了 32 部</b><div><i /><i /><i /><i /></div></div>
          <span className="insight-disclaimer">统计与评分为展示示意</span>
        </div>
        <div className="insight-copy">
          <span className="section-kicker">不止记录，更有洞察</span>
          <h2>你的观看偏好，<br />值得被认真对待。</h2>
          <p>评分走势、收藏统计、年度回顾和好友口味对比，帮助你看见数字背后的选择。</p>
          <ul>
            <li><span>01</span><div><b>作品趋势</b><small>历史评分、排名与收藏变化一目了然</small></div></li>
            <li><span>02</span><div><b>个人统计</b><small>按类型、状态、评分与标签整理收藏</small></div></li>
            <li><span>03</span><div><b>好友对比</b><small>共同收藏、评分相关性与样本置信度</small></div></li>
          </ul>
        </div>
      </section>

      <section className="section platforms-section" id="platforms">
        <div className="section-heading compact">
          <span className="section-kicker">开始下一集</span>
          <h2 id="downloads-title">选择你的设备，<br />下载 MuBangumi。</h2>
          <p>当前正式版 <b>{currentRelease.version}</b> · 构建 {currentRelease.build} · <time dateTime={currentRelease.date}>{currentRelease.date}</time></p>
        </div>
        <div className="platform-grid">
          {platforms.map((platform) => (
            <article className={`platform-card ${platform.available ? "" : "unavailable"}`} key={platform.label}>
              <div className="platform-icon"><PlatformIcon name={platform.icon} /></div>
              <div><h3>{platform.label}</h3><p>{platform.note}</p></div>
              {platform.href ? <a className="button button-primary" href={platform.href}>下载 {platform.label}<ArrowIcon /></a> : <span className="platform-unavailable">暂未发布</span>}
            </article>
          ))}
        </div>
        <div className="download-guidance">
          <p>Android 沿用上一版签名；Windows 请解压到新的空目录。首次使用与升级说明见下方常见问题。</p>
          <div><a className="text-link" href={currentRelease.url} target="_blank" rel="noreferrer">发行说明与校验文件 <ArrowIcon /></a>{giteeReleasesUrl && <a className="text-link" href={giteeReleasesUrl} target="_blank" rel="noreferrer">国内镜像（可能延迟） <ArrowIcon /></a>}</div>
        </div>
      </section>

      <section className="section faq-section" id="faq" aria-labelledby="faq-title">
        <div className="section-heading compact"><span className="section-kicker">先回答几个小问题</span><h2 id="faq-title">下载之后，放心开始。</h2></div>
        <div className="faq-list">{questions.map((question) => <details key={question.title}><summary>{question.title}<span aria-hidden="true">＋</span></summary><p>{question.answer}</p></details>)}</div>
        <p className="faq-note">开源第三方客户端，与 Bangumi 官方无隶属关系。设备体验、真实账号业务与整机内存仍有人工验收项目，详见发行说明。</p>
      </section>

      <section className="opensource-section" id="opensource">
        <div className="opensource-glow" />
        <div className="opensource-copy">
          <span className="opensource-label"><GithubIcon /> OPEN SOURCE</span>
          <h2>看得见的代码，<br />一起变好的客户端。</h2>
          <p>MuBangumi 在 GitHub 开源。你可以查看实现、报告问题，或提交自己的改进。</p>
          <a className="button button-light" href={githubUrl} target="_blank" rel="noreferrer">
            前往 GitHub <ArrowIcon />
          </a>
        </div>
        <div className="code-window" aria-hidden="true">
          <div className="code-title"><i /><i /><i /><span>home_screen.dart</span></div>
          <pre><code><span className="code-purple">class</span> <span className="code-blue">HomeScreen</span> <span className="code-purple">extends</span> StatelessWidget {'{'}{"\n"}  <span className="code-purple">const</span> HomeScreen({'{'}<span className="code-blue">super</span>.key{'}'});{"\n\n"}  <span className="code-gray">@override</span>{"\n"}  Widget <span className="code-blue">build</span>(BuildContext context) {'{'}{"\n"}    <span className="code-purple">return</span> MuBangumi({"\n"}      progress: <span className="code-green">synced</span>,{"\n"}      discovery: <span className="code-green">delightful</span>,{"\n"}    );{"\n"}  {'}'}{"\n"}{'}'}</code></pre>
        </div>
      </section>

      <section className="final-cta">
        <Image src={faviconUrl} alt="MuBangumi" width="74" height="74" />
        <h2>下一集，从这里开始。</h2>
        <p>打开 MuBangumi，把喜欢的作品和每一点进度好好收起来。</p>
        <div className="hero-actions">
          <a className="button button-primary" href="#platforms">选择设备并下载 <ArrowIcon /></a>
          <a className="button button-secondary" href={releasesUrl} target="_blank" rel="noreferrer">查看最新版本 <ArrowIcon /></a>
          <a className="button button-secondary" href={githubUrl} target="_blank" rel="noreferrer"><GithubIcon /> 浏览项目</a>
        </div>
      </section>

      <section className="references-section" id="references">
        <div className="references-heading">
          <span className="section-kicker">REFERENCE & THANKS</span>
          <h2>参考与致谢</h2>
          <p>感谢这些项目、服务与社区，让 MuBangumi 的数据能力、产品体验和跨端开发成为可能。</p>
        </div>
        <div className="reference-grid">
          <a href="https://bgm.tv/" target="_blank" rel="noreferrer">
            <span className="reference-number">01</span>
            <div><small>数据与社区</small><h3>Bangumi 番组计划</h3><p>条目、收藏、进度、社区与 OAuth 能力的核心来源。</p></div>
            <i>↗</i>
          </a>
          <a href="https://github.com/bangumi/api" target="_blank" rel="noreferrer">
            <span className="reference-number">02</span>
            <div><small>开放接口</small><h3>Bangumi API</h3><p>公开 OpenAPI 规范及接口文档，为客户端数据访问提供基础。</p></div>
            <i>↗</i>
          </a>
          <a href="https://netaba.re/" target="_blank" rel="noreferrer">
            <span className="reference-number">03</span>
            <div><small>趋势数据</small><h3>netaba.re</h3><p>为历史评分、排名、收藏变化与口碑趋势提供公开数据。</p></div>
            <i>↗</i>
          </a>
          <a href="https://bangumi.tv/dev/garage" target="_blank" rel="noreferrer">
            <span className="reference-number">04</span>
            <div><small>功能灵感</small><h3>超合金组件格纳库</h3><p>评分详情、好友观看状态和讨论高亮等体验的灵感来源。</p></div>
            <i>↗</i>
          </a>
          <a href="https://zcode.z.ai/en" target="_blank" rel="noreferrer">
            <span className="reference-number">05</span>
            <div><small>网页呈现</small><h3>ZCode</h3><p>本项目主页首屏可交互产品演示的呈现方式参考。</p></div>
            <i>↗</i>
          </a>
          <a href="https://flutter.dev/" target="_blank" rel="noreferrer">
            <span className="reference-number">06</span>
            <div><small>跨端框架</small><h3>Flutter</h3><p>MuBangumi 在 Android、iOS 与 Windows 上共享代码的技术基础。</p></div>
            <i>↗</i>
          </a>
          <a href="https://shorebird.dev/" target="_blank" rel="noreferrer">
            <span className="reference-number">07</span>
            <div><small>发布工具</small><h3>Shorebird</h3><p>为支持的平台提供 Dart 代码热更新能力。</p></div>
            <i>↗</i>
          </a>
        </div>
        <p className="reference-note">以上仅表示数据来源、技术使用或设计与功能参考，不代表任何官方合作、隶属关系或背书。</p>
      </section>

      <footer>
        <div className="footer-brand">
          <Image src={faviconUrl} alt="" width="34" height="34" />
          <div><b>MuBangumi</b><span>认真记录每一部喜欢。</span></div>
        </div>
        <div className="footer-links">
          <a href={githubUrl} target="_blank" rel="noreferrer">GitHub</a>
          <a href={`${githubUrl}/issues`} target="_blank" rel="noreferrer">问题反馈</a>
          <a href="https://github.com/bangumi/api" target="_blank" rel="noreferrer">Bangumi API</a>
          <a href="#faq">常见问题</a>
          <a href="#references">参考与致谢</a>
        </div>
        <p>非官方客户端，与 Bangumi 番组计划官方无隶属关系。</p>
      </footer>
    </main>
  );
}
