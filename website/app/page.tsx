import type { ReactNode } from "react";
import Image from "next/image";
import { ProductDemo } from "./ProductDemo";
import { currentRelease } from "./release";

export const dynamic = "force-static";

const githubUrl = "https://github.com/wweiyi2004/MuBangumi";
const releasesUrl = `${githubUrl}/releases`;
const giteeRepository = process.env.NEXT_PUBLIC_GITEE_REPOSITORY ?? "";
const giteeReleasesUrl = /^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+$/.test(giteeRepository) &&
  !giteeRepository.split("/").some((part) => part === "." || part === "..")
  ? `https://gitee.com/${giteeRepository}/releases` : null;
const faviconUrl = `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/favicon.svg`;
const [releaseYear, releaseMonth, releaseDay] = currentRelease.date.split("-").map(Number);
const releaseDate = `${releaseYear} 年 ${releaseMonth} 月 ${releaseDay} 日`;

const features = [
  {
    icon: "check",
    title: "追番进度，清楚一点",
    description: "首页点格子、一键标记下一集，打卡热力图记下自己的节奏；网络恢复后继续同步。",
  },
  {
    icon: "sparkles",
    title: "发现真正想看的",
    description: "按季度、口碑趋势、年份评分和标签组合查找，还能隐藏已收藏，不再反复翻榜单。",
  },
  {
    icon: "users",
    title: "社区就在手边",
    description: "时间线、超展开、小组话题、好友和站内短信，都用更适合手机的方式呈现。",
  },
  {
    icon: "calendar",
    title: "自己的新番表",
    description: "按周几安排本季追番，和官方每日放送互不干扰，还能打印成季度海报分享。",
  },
  {
    icon: "chart",
    title: "看懂评分变化",
    description: "对比多部作品的历史评分，查看收藏统计和好友口味，不只盯着一个数字。",
  },
  {
    icon: "shield",
    title: "数据由你掌握",
    description: "本地备注、好友分组与收藏快照留在设备上；配置迁移有密码保护，登录凭据单独存储。",
  },
] as const;

const updates = [
  { title: "章节打卡热力图", text: "追番页按账号记录每次看过；取消和撤销会同步调整，不补填启用前的历史。" },
  { title: "番剧单与评分对比", text: "整理、分享番剧单，对比多部作品的评分历史，查看完整制作人员与个人介绍。" },
  { title: "外观按自己的喜好", text: "自定义配色，按需下载或导入本地字体；菜单圆角和品牌配色统一。" },
  { title: "更轻的内存占用", text: "图片按展示尺寸解码，临时缓存有上限；隐藏页面暂停动画，内存告警时主动释放。" },
] as const;

const questions = [
  {
    title: "第一次安装，选哪一个？",
    answer: "Android 下载通用 APK，按系统提示确认安装。Windows 下载 x64 ZIP，解压到新的空目录后运行 mubangumi.exe。本版没有 iOS 安装包。",
  },
  {
    title: "已有旧版，怎样升级？",
    answer: "应用内的更新提醒会下载并校验新版本。手动升级时，Android 可直接覆盖安装；Windows 请解压到新的空目录，不要覆盖旧目录。升级前可以在设置里用配置导出备份本地设置。",
  },
  {
    title: "哪些内容能同步，哪些留在设备上？",
    answer: "收藏和章节进度通过 Bangumi 账号同步。本地备注、好友分组、外观设置和草稿只保存在本机；配置导出不包含登录凭据、网页登录会话和待同步的写入。",
  },
  {
    title: "网页上的演示会修改我的 Bangumi 账号吗？",
    answer: "不会。演示只用示例数据，进度、筛选和贴贴只保留在当前页面，刷新即重置。它是交互示意，不是软件截图，也不是实时评分。",
  },
  {
    title: "GitHub 下载不顺畅怎么办？",
    answer: "可以试试下载区的 Gitee 镜像，但镜像同步可能晚于 GitHub。请核对版本号和文件名；每个版本的 SHA-256 校验和都附在 GitHub 发行页里。",
  },
  {
    title: "遇到问题在哪里反馈？",
    answer: "请在 GitHub Issues 里写明系统、软件版本和复现步骤。不要公开 Token、Cookie、私信内容或完整的个人数据库。",
  },
] as const;

const references = [
  { href: "https://bgm.tv/", kind: "数据与社区", title: "Bangumi 番组计划", text: "条目、收藏、进度、社区与 OAuth 能力的核心来源。" },
  { href: "https://github.com/bangumi/api", kind: "开放接口", title: "Bangumi API", text: "公开 OpenAPI 规范及接口文档，为客户端数据访问提供基础。" },
  { href: "https://netaba.re/", kind: "趋势数据", title: "netaba.re", text: "为历史评分、排名、收藏变化与口碑趋势提供公开数据。" },
  { href: "https://bangumi.tv/dev/garage", kind: "功能灵感", title: "超合金组件格纳库", text: "评分详情、好友观看状态和讨论高亮等体验的灵感来源。" },
  { href: "https://zcode.z.ai/en", kind: "网页呈现", title: "ZCode", text: "本项目主页首屏可交互产品演示的呈现方式参考。" },
  { href: "https://flutter.dev/", kind: "跨端框架", title: "Flutter", text: "MuBangumi 在 Android、iOS 与 Windows 上共享代码的技术基础。" },
  { href: "https://shorebird.dev/", kind: "发布工具", title: "Shorebird", text: "为支持的平台提供 Dart 代码热更新能力。" },
] as const;

// A fixed, irregular "watched" pattern for the decorative episode grid, so
// server and client render the same cells.
const gridCells = Array.from({ length: 84 }, (_, index) => {
  const value = (index * 37 + 11) % 23;
  return value < 4 ? "on" : value < 6 ? "soft" : "";
});

function ArrowIcon() {
  return (
    <svg viewBox="0 0 20 20" aria-hidden="true">
      <path d="M4 10h12m-5-5 5 5-5 5" />
    </svg>
  );
}

function DownloadIcon() {
  return (
    <svg viewBox="0 0 20 20" aria-hidden="true">
      <path d="M10 3v10m-4.5-4.5L10 13l4.5-4.5M4 16.5h12" />
    </svg>
  );
}

function GithubIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="fill-icon">
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

function EpisodeTicks({ watched, total = 6 }: { watched: number; total?: number }) {
  return (
    <span className="ep-ticks" aria-hidden="true">
      {Array.from({ length: total }, (_, index) => <i className={index < watched ? "on" : ""} key={index} />)}
    </span>
  );
}

export default function Home() {
  return (
    <>
      <a className="skip-link" href="#main-content">跳到主要内容</a>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="MuBangumi 首页">
          <Image src={faviconUrl} alt="" width="32" height="32" priority />
          <span>MuBangumi</span>
        </a>
        <nav aria-label="主导航">
          <a href="#features">功能</a>
          <a href="#updates">更新</a>
          <a href="#platforms">下载</a>
          <a href="#faq">帮助</a>
          <a href="#references">致谢</a>
        </nav>
        <a className="header-github" href={githubUrl} target="_blank" rel="noreferrer" aria-label="GitHub 仓库">
          <GithubIcon /><span>GitHub</span>
        </a>
      </header>

      <main id="main-content">
        <section className="hero" id="top">
          <div className="hero-grid" aria-hidden="true">
            {gridCells.map((cell, index) => <i className={cell} key={index} />)}
          </div>
          <div className="hero-copy">
            <a className="release-pill" href="#updates">
              <span>v{currentRelease.version}</span>{releaseDate}发布 <ArrowIcon />
            </a>
            <h1>
              追番这件事，<br />
              <mark>简单又好看。</mark>
            </h1>
            <p className="hero-description">
              第三方 Bangumi 客户端。把收藏、进度、发现与社区收进一个舒服的应用，
              在 Android 和 Windows 上认真记录每一部喜欢。
            </p>
            <div className="hero-actions">
              <a className="button button-primary" href="#platforms">
                <DownloadIcon /> 免费下载
              </a>
              <a className="button button-ghost" href={githubUrl} target="_blank" rel="noreferrer">
                <GithubIcon /> 查看源码
              </a>
            </div>
            <ul className="hero-meta" aria-label="项目特点">
              <li>开源免费</li>
              <li>深浅主题</li>
              <li>手机与桌面</li>
            </ul>
          </div>

          <ProductDemo />
        </section>

        <section className="section updates-section" id="updates" aria-labelledby="updates-title">
          <div className="section-heading split">
            <div>
              <span className="kicker">本期更新 · v{currentRelease.version}</span>
              <h2 id="updates-title">你的习惯，多一点自己的样子。</h2>
            </div>
            <a className="text-link" href={currentRelease.url} target="_blank" rel="noreferrer">
              完整更新说明 <ArrowIcon />
            </a>
          </div>
          <ol className="update-list">
            {updates.map((update, index) => (
              <li key={update.title}>
                <span className="update-index">{String(index + 1).padStart(2, "0")}</span>
                <h3>{update.title}</h3>
                <p>{update.text}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="section features-section" id="features" aria-labelledby="features-title">
          <div className="section-heading">
            <span className="kicker">不只是一张番表</span>
            <h2 id="features-title">从“想看”到“看完”，<br />每一步都更顺手。</h2>
            <p>围绕真实的追番习惯设计，不把常用操作藏进层层菜单。</p>
          </div>
          <div className="feature-board">
            {features.map((feature, index) => (
              <article className="feature-card" key={feature.title}>
                <header>
                  <span className="ep-label">EP.{String(index + 1).padStart(2, "0")}</span>
                  <EpisodeTicks watched={index + 1} />
                </header>
                <div className="feature-icon"><FeatureIcon name={feature.icon} /></div>
                <h3>{feature.title}</h3>
                <p>{feature.description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="section insight-section" aria-labelledby="insight-title">
          <div className="insight-copy">
            <span className="kicker">不止记录，更有洞察</span>
            <h2 id="insight-title">你的观看偏好，<br />值得被认真对待。</h2>
            <p>评分走势、收藏统计、年度回顾和好友口味对比，帮你看见数字背后的选择。</p>
            <dl>
              <div><dt>作品趋势</dt><dd>历史评分、排名与收藏变化，多部作品放在一起比</dd></div>
              <div><dt>个人统计</dt><dd>按类型、状态、评分与标签整理收藏，图表可点</dd></div>
              <div><dt>好友对比</dt><dd>共同收藏、评分相关性与样本置信度</dd></div>
            </dl>
          </div>
          <figure className="insight-visual" aria-label="评分趋势示意，示例数据">
            <div className="insight-head">
              <span>评分趋势</span><small>示例数据 · 近 30 天</small>
            </div>
            <div className="score-line"><strong>8.6</strong><span className="rise">▲ 0.4</span></div>
            <svg className="chart" viewBox="0 0 460 150" preserveAspectRatio="none" aria-hidden="true">
              <defs>
                <linearGradient id="chartFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0" className="chart-stop" stopOpacity=".32" />
                  <stop offset="1" className="chart-stop" stopOpacity="0" />
                </linearGradient>
              </defs>
              <path className="chart-compare" d="M0 110 C60 112 90 104 130 108 S200 96 240 100 S320 90 360 94 S420 86 460 88" />
              <path className="chart-fill" d="M0 124 C55 118 74 96 116 103 S181 79 225 88 S292 54 330 63 S390 31 460 21 L460 150 L0 150Z" />
              <path className="chart-line" d="M0 124 C55 118 74 96 116 103 S181 79 225 88 S292 54 330 63 S390 31 460 21" />
            </svg>
            <figcaption>
              <span><i className="legend-main" />本作</span>
              <span><i className="legend-compare" />同季对比</span>
            </figcaption>
          </figure>
        </section>

        <section className="section download-section" id="platforms" aria-labelledby="download-title">
          <div className="section-heading split">
            <div>
              <span className="kicker">下载 · v{currentRelease.version} · build {currentRelease.build}</span>
              <h2 id="download-title">下一集，从这里开始。</h2>
            </div>
            <a className="text-link" href={releasesUrl} target="_blank" rel="noreferrer">
              全部版本 <ArrowIcon />
            </a>
          </div>
          <div className="download-grid">
            <article className="download-card">
              <div className="platform-icon"><PlatformIcon name="android" /></div>
              <h3>Android</h3>
              <p>通用 APK，适用于手机与平板</p>
              <code>{currentRelease.assets.android.file}</code>
              <a className="button button-primary" href={currentRelease.assets.android.url} aria-label="下载 Android">
                <DownloadIcon /> 下载 APK
              </a>
            </article>
            <article className="download-card">
              <div className="platform-icon"><PlatformIcon name="windows" /></div>
              <h3>Windows</h3>
              <p>x64 便携 ZIP，解压到新的空目录后运行</p>
              <code>{currentRelease.assets.windows.file}</code>
              <a className="button button-primary" href={currentRelease.assets.windows.url} aria-label="下载 Windows">
                <DownloadIcon /> 下载 ZIP
              </a>
            </article>
            <article className="download-card unavailable">
              <div className="platform-icon"><PlatformIcon name="apple" /></div>
              <h3>iOS</h3>
              <p>本版未提供安装包</p>
              <small>需要在 macOS + Xcode 环境中签名构建。</small>
            </article>
          </div>
          <p className="download-note">
            {giteeReleasesUrl && <><a href={giteeReleasesUrl} target="_blank" rel="noreferrer">国内镜像（Gitee）</a><span aria-hidden="true">·</span></>}
            <a href={currentRelease.url} target="_blank" rel="noreferrer">SHA-256 校验和与来源记录</a>
            <span aria-hidden="true">·</span>
            <span>2.4.2 为整包更新</span>
          </p>
        </section>

        <section className="section faq-section" id="faq" aria-labelledby="faq-title">
          <div className="section-heading">
            <span className="kicker">常见问题</span>
            <h2 id="faq-title">装之前，<br />先看看这些。</h2>
            <p>没有找到答案？<a href={`${githubUrl}/issues`} target="_blank" rel="noreferrer">在 GitHub 上提问</a>。</p>
          </div>
          <div className="faq-list">
            {questions.map((question) => (
              <details key={question.title}>
                <summary>{question.title}</summary>
                <p>{question.answer}</p>
              </details>
            ))}
          </div>
        </section>

        <section className="opensource-section" id="opensource" aria-labelledby="opensource-title">
          <div className="opensource-copy">
            <span className="kicker">Open Source</span>
            <h2 id="opensource-title">看得见的代码，<br />一起变好的客户端。</h2>
            <p>MuBangumi 在 GitHub 开源。你可以查看实现、报告问题，或提交自己的改进。</p>
            <a className="button button-primary" href={githubUrl} target="_blank" rel="noreferrer">
              <GithubIcon /> 前往 GitHub
            </a>
          </div>
          <div className="opensource-grid" aria-hidden="true">
            {Array.from({ length: 7 }, (_, row) => (
              <div key={row}>
                <b>{["一", "二", "三", "四", "五", "六", "日"][row]}</b>
                {Array.from({ length: 12 }, (_, col) => {
                  const value = (row * 12 + col) * 29 % 17;
                  return <i className={value < 5 ? "on" : value < 9 ? "soft" : ""} key={col} />;
                })}
              </div>
            ))}
          </div>
        </section>

        <section className="section references-section" id="references" aria-labelledby="references-title">
          <div className="section-heading">
            <span className="kicker">Reference &amp; Thanks</span>
            <h2 id="references-title">参考与致谢</h2>
            <p>感谢这些项目、服务与社区，让 MuBangumi 的数据能力、产品体验和跨端开发成为可能。</p>
          </div>
          <ul className="reference-list">
            {references.map((reference, index) => (
              <li key={reference.href}>
                <a href={reference.href} target="_blank" rel="noreferrer">
                  <span className="reference-number">{String(index + 1).padStart(2, "0")}</span>
                  <small>{reference.kind}</small>
                  <b>{reference.title}</b>
                  <span className="reference-text">{reference.text}</span>
                  <i aria-hidden="true">↗</i>
                </a>
              </li>
            ))}
          </ul>
          <p className="reference-note">以上仅表示数据来源、技术使用或设计与功能参考，不代表任何官方合作、隶属关系或背书。</p>
        </section>
      </main>

      <footer>
        <div className="footer-brand">
          <Image src={faviconUrl} alt="" width="28" height="28" />
          <div><b>MuBangumi</b><span>认真记录每一部喜欢。</span></div>
        </div>
        <nav className="footer-links" aria-label="页脚链接">
          <a href={githubUrl} target="_blank" rel="noreferrer">GitHub</a>
          <a href={`${githubUrl}/issues`} target="_blank" rel="noreferrer">问题反馈</a>
          <a href="https://github.com/bangumi/api" target="_blank" rel="noreferrer">Bangumi API</a>
          <a href="#references">参考与致谢</a>
        </nav>
        <p>非官方客户端，与 Bangumi 番组计划官方无隶属关系。</p>
      </footer>
    </>
  );
}
