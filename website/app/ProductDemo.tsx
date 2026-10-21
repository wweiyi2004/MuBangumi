"use client";

import { useEffect, useRef, useState } from "react";
import { icons, type IconName } from "./icons";

// Layouts, labels and colors mirror the client's phone screens
// (lib/screens/home_page.dart, library_page.dart, discover_page.dart,
// messages_page.dart and the profile home). All data is fictional.

function Icon({ name, size = 20, className = "" }: { name: IconName; size?: number; className?: string }) {
  return (
    <svg
      className={`mi ${className}`}
      viewBox="0 0 24 24"
      width={size}
      height={size}
      aria-hidden="true"
      dangerouslySetInnerHTML={{ __html: icons[name] }}
    />
  );
}

const tabs = [
  { id: "track", label: "追番", off: "trackOff", on: "trackOn", aria: "打开追番" },
  { id: "library", label: "收藏", off: "libraryOff", on: "libraryOn", aria: "打开收藏" },
  { id: "discover", label: "发现", off: "exploreOff", on: "exploreOn", aria: "打开发现" },
  { id: "message", label: "消息", off: "messageOff", on: "messageOn", aria: "打开消息" },
  { id: "me", label: "我的", off: "personOff", on: "personOn", aria: "打开我的" },
] as const satisfies readonly { id: string; label: string; off: IconName; on: IconName; aria: string }[];

type TabId = (typeof tabs)[number]["id"];

const shows = [
  { title: "葬送的芙莉莲", episode: 24, total: 28, score: "9.1", cover: "cover-a" },
  { title: "迷宫饭", episode: 18, total: 24, score: "8.4", cover: "cover-b" },
  { title: "跃动青春", episode: 9, total: 12, score: "8.2", cover: "cover-c" },
  { title: "宝石之国", episode: 6, total: 12, score: "8.7", cover: "cover-d" },
] as const;

const shortcuts = [
  { icon: "calendarWeek", label: "新番表", color: "#7c6ce7" },
  { icon: "liveTv", label: "每日放送", color: "#f09199" },
  { icon: "autoAwesome", label: "番会荐", color: "#e38a3f" },
  { icon: "travelExplore", label: "找新番", color: "#2ca69a" },
] as const;

type Status = "想看" | "看过" | "在看" | "搁置" | "抛弃";
const statuses: Status[] = ["想看", "看过", "在看", "搁置", "抛弃"];

const libraryExtras = [
  { title: "摇曳露营△", status: "想看", episode: 0, total: 12, score: "8.1", cover: "cover-c" },
  { title: "少女终末旅行", status: "想看", episode: 0, total: 12, score: "8.7", cover: "cover-a" },
  { title: "四叠半神话大系", status: "看过", episode: 11, total: 11, score: "8.6", cover: "cover-d" },
  { title: "来自深渊", status: "搁置", episode: 5, total: 13, score: "8.6", cover: "cover-b" },
] as const;

const subjectTypes = [
  { id: "book", label: "书籍", icon: "book" },
  { id: "anime", label: "动画", icon: "movie" },
  { id: "music", label: "音乐", icon: "music" },
  { id: "game", label: "游戏", icon: "game" },
  { id: "real", label: "三次元", icon: "liveTv" },
] as const;

const seasonRanking = [
  { title: "夏日放送", score: "8.1", rank: 12, votes: "2,341", cover: "cover-a" },
  { title: "星海来信", score: "7.9", rank: 25, votes: "1,872", cover: "cover-c" },
  { title: "迷宫饭", score: "8.4", rank: 0, votes: "", cover: "cover-b", tracked: 1 },
  { title: "雨后车站", score: "7.8", rank: 41, votes: "1,205", cover: "cover-d" },
] as const;

const hotGroups = [
  { name: "一起补旧番", meta: "286 成员 · 32 话题" },
  { name: "周末游戏茶话会", meta: "128 成员 · 32 话题" },
] as const;

const topics = [
  { id: 1, title: "最近有什么想推荐给朋友的作品？", group: "一起补旧番", replies: 24 },
  { id: 2, title: "聊聊让你反复回味的结尾", group: "一起补旧番", replies: 18 },
  { id: 3, title: "周末一起看：本周讨论", group: "一起补旧番", replies: 9 },
] as const;

const conversations = [
  { id: 1, name: "小夏", avatar: "小", note: "周末补番", last: "等更新后再一起聊聊吧。", time: "14:32" },
  { id: 2, name: "Mori", avatar: "M", note: "", last: "新番表排好了，发你看看", time: "昨天" },
] as const;

const notifications = [
  { text: "小夏 回复了你的话题「聊聊让你反复回味的结尾」", time: "8 分钟前" },
  { text: "Mori 关注了你", time: "1 小时前" },
  { text: "一起补旧番 有 3 条新讨论", time: "今天" },
] as const;

type Message = { id: number; mine: boolean; text: string; time: string };

const initialMessages: Message[] = [
  { id: 1, mine: false, text: "这周的新番看了吗？画面和配乐都很喜欢。", time: "今天 14:30" },
  { id: 2, mine: true, text: "看了，最后那段很精彩。", time: "今天 14:31" },
  { id: 3, mine: false, text: "等更新后再一起聊聊吧。", time: "今天 14:32" },
];

// 20 weeks ending on Thursday 10/2. A fixed pattern keeps server and client
// renders identical; today's cell comes from state.
const heatWeeks = 20;
const todayRow = 3;
const heatHistory = Array.from({ length: heatWeeks * 7 }, (_, index) => {
  const value = (index * 53 + 7) % 17;
  return value < 6 ? 0 : value < 10 ? 1 + (index % 2) : value < 13 ? 3 + (index % 3) : value < 15 ? 7 : 11;
});

function heatLevel(count: number) {
  return count === 0 ? 0 : count <= 2 ? 1 : count <= 5 ? 2 : count <= 9 ? 3 : 4;
}

export function ProductDemo() {
  const [activeTab, setActiveTab] = useState<TabId>("track");
  const [episodes, setEpisodes] = useState<number[]>(() => shows.map((show) => show.episode));
  const [pinned, setPinned] = useState<number[]>([0]);
  const [todayCount, setTodayCount] = useState(2);
  const [picker, setPicker] = useState<number | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [libraryType, setLibraryType] = useState<string>("anime");
  const [libraryStatus, setLibraryStatus] = useState<Status>("在看");
  const [statusMenu, setStatusMenu] = useState(false);
  const [discoverTab, setDiscoverTab] = useState<"works" | "topics">("works");
  const [discoverType, setDiscoverType] = useState<string>("anime");
  const [readTopics, setReadTopics] = useState<number[]>([]);
  const [messageTab, setMessageTab] = useState<"pm" | "groups" | "notify">("pm");
  const [openChat, setOpenChat] = useState<number | null>(null);
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [draft, setDraft] = useState("");
  const [liked, setLiked] = useState(false);
  const toastTimer = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    };
  }, []);

  const showToast = (text: string) => {
    setToast(text);
    if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 2400);
  };

  const setEpisode = (index: number, episode: number) => {
    const show = shows[index];
    const next = Math.max(0, Math.min(episode, show.total));
    const delta = next - episodes[index];
    if (delta === 0) return;
    setEpisodes((current) => current.map((value, i) => (i === index ? next : value)));
    // The heatmap counts check-ins and takes them back on undo, never below zero.
    setTodayCount((count) => Math.max(0, count + delta));
    showToast(`${show.title} · 已记录 ${next} 集`);
  };

  const markNextEpisode = (index: number) => setEpisode(index, episodes[index] + 1);

  const togglePin = (index: number) =>
    setPinned((current) => (current.includes(index) ? current.filter((i) => i !== index) : [...current, index]));

  const sendMessage = () => {
    const text = draft.trim();
    if (!text) return;
    setMessages((current) => [...current, { id: current.length + 1, mine: true, text, time: "刚刚" }]);
    setDraft("");
  };

  const ordered = shows
    .map((show, index) => ({ show, index }))
    .sort((a, b) => Number(pinned.includes(b.index)) - Number(pinned.includes(a.index)));
  const heatTotal = heatHistory.slice(0, (heatWeeks - 1) * 7 + todayRow).reduce((sum, value) => sum + value, 0) + todayCount;

  const library = [
    ...shows.map((show, index) => ({
      title: show.title,
      status: (episodes[index] === show.total ? "看过" : "在看") as Status,
      episode: episodes[index],
      total: show.total,
      score: show.score,
      cover: show.cover,
      index,
    })),
    ...libraryExtras.map((item) => ({ ...item, status: item.status as Status, index: -1 })),
  ];
  const doing = library.filter((item) => item.status === "在看").length;
  const completed = library.filter((item) => item.status === "看过").length;
  const visibleLibrary = libraryType === "anime" || libraryType === "all"
    ? library.filter((item) => item.status === libraryStatus)
    : [];

  return (
    <div className="app-showcase" aria-label="可点击的 MuBangumi 产品演示">
      <div className="demo-hint"><span /> 可交互演示 · 按真实界面还原 · 示例数据</div>
      <div className="phone">
        <div className="phone-status" aria-hidden="true"><b>21:24</b><span /></div>
        <div className="phone-screen">
          <div className="demo-panel" key={`${activeTab}-${openChat ?? ""}`} role="tabpanel" aria-live="polite">
            {activeTab === "track" && (
              <>
                <div className="home-header">
                  <div>
                    <h2 className="greeting">晚上好<span>21:24</span></h2>
                    <small>10 月 2 日 · 星期四</small>
                  </div>
                  <div className="icon-row" aria-hidden="true">
                    <Icon name="notifications" />
                    <Icon name="sync" />
                    <Icon name="moreVert" />
                  </div>
                </div>
                <div className="shortcut-grid">
                  {shortcuts.map((item) => (
                    <button
                      type="button"
                      key={item.label}
                      onClick={() => item.label === "找新番" ? setActiveTab("discover") : showToast(`演示中未包含「${item.label}」`)}
                    >
                      <span className="shortcut-icon" style={{ color: item.color }}><Icon name={item.icon} size={22} /></span>
                      {item.label}
                    </button>
                  ))}
                </div>

                <section className="app-card heatmap-card" aria-label="每日追番">
                  <div className="card-top">
                    <h3>每日追番</h3>
                    <small>今日 {todayCount} 格 · 近 {heatWeeks * 7} 天 {heatTotal} 格</small>
                  </div>
                  <div className="heatmap">
                    <div className="heat-days" aria-hidden="true"><i>一</i><i /><i>三</i><i /><i>五</i><i /><i /></div>
                    <div className="heat-grid" aria-hidden="true">
                      {Array.from({ length: heatWeeks }, (_, week) => (
                        <div key={week}>
                          {Array.from({ length: 7 }, (_, day) => {
                            const last = week === heatWeeks - 1;
                            if (last && day > todayRow) return <i className="future" key={day} />;
                            const count = last && day === todayRow ? todayCount : heatHistory[week * 7 + day];
                            return <i className={`l${heatLevel(count)}`} key={day} />;
                          })}
                        </div>
                      ))}
                    </div>
                  </div>
                  <div className="heat-foot">
                    <small>本机章节打卡 · 从启用后开始记录</small>
                    <span aria-hidden="true">少<i className="l0" /><i className="l1" /><i className="l2" /><i className="l3" /><i className="l4" />多</span>
                  </div>
                </section>

                <div className="section-row">
                  <h3>继续追</h3>
                  <div>
                    <span className="icon-button" aria-hidden="true"><Icon name="swapVert" /></span>
                    <button type="button" className="text-button" onClick={() => setActiveTab("library")}>查看全部（{shows.length}）</button>
                  </div>
                </div>
                <div className="continue-list">
                  {ordered.map(({ show, index }) => {
                    const episode = episodes[index];
                    const done = episode === show.total;
                    const isPinned = pinned.includes(index);
                    return (
                      <article className="continue-tile" key={show.title}>
                        <span className={`cover ${show.cover}`} />
                        <div className="tile-copy">
                          <h4>{show.title}</h4>
                          <p>已记录 {episode} / {show.total} 集</p>
                          <span className="linear"><i style={{ width: `${(episode / show.total) * 100}%` }} /></span>
                          <div className="tile-actions">
                            <button type="button" className="text-button with-icon" onClick={() => markNextEpisode(index)} disabled={done}>
                              <Icon name={done ? "check" : "addTask"} size={18} />{done ? "已看完" : "看完下一集"}
                            </button>
                            <button type="button" className="icon-button" aria-label={`选择集数：${show.title}`} onClick={() => setPicker(index)}>
                              <Icon name="gridView" size={19} />
                            </button>
                            <button
                              type="button"
                              className={`icon-button ${isPinned ? "pinned" : ""}`}
                              aria-label={isPinned ? `取消置顶：${show.title}` : `置顶到首页：${show.title}`}
                              aria-pressed={isPinned}
                              onClick={() => togglePin(index)}
                            >
                              <Icon name={isPinned ? "pinOn" : "pinOff"} size={18} />
                            </button>
                          </div>
                        </div>
                      </article>
                    );
                  })}
                </div>
                <p className="footnote">进行中 {doing} · 已完成 {completed} · 总收藏 {library.length}</p>
              </>
            )}

            {activeTab === "library" && (
              <>
                <h2 className="title-large">我的收藏</h2>
                <div className="library-actions">
                  <button type="button" onClick={() => showToast("演示中未包含「番剧单」")}>番剧单</button>
                  <button type="button" onClick={() => showToast("演示中未包含「统计与回顾」")}>统计与回顾</button>
                  <button type="button" onClick={() => showToast("演示中未包含「批量整理」")}>批量整理</button>
                </div>
                <small className="muted">找到 {visibleLibrary.length} 部</small>
                <div className="search-row">
                  <span className="search-field"><Icon name="search" />在收藏中搜索</span>
                  <div className="menu-anchor">
                    <button
                      type="button"
                      className="icon-button"
                      aria-label="按状态筛选"
                      aria-expanded={statusMenu}
                      onClick={() => setStatusMenu((open) => !open)}
                    >
                      <Icon name="filterList" />
                    </button>
                    {statusMenu && (
                      <div className="popup-menu" role="menu">
                        {statuses.map((status) => (
                          <button
                            type="button"
                            role="menuitemradio"
                            aria-checked={libraryStatus === status}
                            key={status}
                            onClick={() => { setLibraryStatus(status); setStatusMenu(false); }}
                          >{status}</button>
                        ))}
                      </div>
                    )}
                  </div>
                  <span className="icon-button tonal" aria-hidden="true"><Icon name="tune" /></span>
                </div>
                <div className="chip-row" aria-label="作品类型">
                  <button type="button" className="chip" aria-pressed={libraryType === "all"} onClick={() => setLibraryType("all")}>
                    {libraryType === "all" && <Icon name="check" size={16} className="chip-check" />}全部类型
                  </button>
                  {subjectTypes.map((type) => (
                    <button type="button" className="chip" aria-pressed={libraryType === type.id} onClick={() => setLibraryType(type.id)} key={type.id}>
                      <Icon name={libraryType === type.id ? "check" : type.icon} size={16} className={libraryType === type.id ? "chip-check" : ""} />{type.label}
                    </button>
                  ))}
                </div>
                <small className="muted status-line">状态：{libraryStatus}</small>
                <div className="subject-list">
                  {visibleLibrary.length === 0 && <p className="empty">示例收藏里没有这一类作品</p>}
                  {visibleLibrary.map((item) => (
                    <article className="subject-tile collection-row" key={item.title}>
                      <span className={`cover ${item.cover}`} />
                      <div>
                        <h4>{item.title}</h4>
                        <b className="status-label">{item.status}</b>
                        <p>看到 {item.episode} / {item.total}<span><Icon name="star" size={16} />{item.score}</span></p>
                        <span className="linear thick"><i style={{ width: `${(item.episode / item.total) * 100}%` }} /></span>
                      </div>
                      {item.index >= 0 && (
                        <div className="tile-side">
                          <button type="button" className="icon-button outlined" aria-label={`点格子：${item.title}`} onClick={() => setPicker(item.index)}><Icon name="gridView" size={16} /></button>
                          <button type="button" className="icon-button tonal" aria-label={`看完下一集：${item.title}`} onClick={() => markNextEpisode(item.index)} disabled={item.episode === item.total}><Icon name="add" size={16} /></button>
                        </div>
                      )}
                    </article>
                  ))}
                </div>
              </>
            )}

            {activeTab === "discover" && (
              <>
                <h2 className="title-hub">发现</h2>
                <div className="tab-bar" role="tablist">
                  <button type="button" role="tab" aria-selected={discoverTab === "works"} onClick={() => setDiscoverTab("works")}>找作品</button>
                  <button type="button" role="tab" aria-selected={discoverTab === "topics"} onClick={() => setDiscoverTab("topics")}>超展开</button>
                </div>
                {discoverTab === "works" ? (
                  <>
                    <div className="search-row">
                      <span className="search-field"><Icon name="search" />搜索动画，例如：迷宫饭</span>
                      <span className="icon-button" aria-hidden="true"><Icon name="tune" /></span>
                    </div>
                    <div className="chip-row" aria-label="作品类型">
                      {subjectTypes.map((type) => (
                        <button type="button" className="chip" aria-pressed={discoverType === type.id} onClick={() => setDiscoverType(type.id)} key={type.id}>
                          <Icon name={discoverType === type.id ? "check" : type.icon} size={16} className={discoverType === type.id ? "chip-check" : ""} />{type.label}
                        </button>
                      ))}
                    </div>
                    <div className="section-row tight">
                      <h3>{discoverType === "anime" ? "动画季度榜" : `${subjectTypes.find((type) => type.id === discoverType)?.label}年度榜`}</h3>
                      <span className="icon-button amber" aria-hidden="true"><Icon name="trend" /></span>
                    </div>
                    <small className="muted">{discoverType === "anime" ? "2026 · 秋季（10月）" : "2026"}</small>
                    <div className="poster-grid">
                      {seasonRanking.map((item) => {
                        const tracked: number = "tracked" in item ? item.tracked : -1;
                        const episode = tracked >= 0 ? episodes[tracked] : 0;
                        const total = tracked >= 0 ? shows[tracked].total : 0;
                        return (
                          <article className="poster-card" key={item.title}>
                            <span className={`cover ${item.cover}`}>
                              <b className="score-badge"><Icon name="star" size={12} />{item.score}</b>
                              <em>{tracked >= 0 ? `看到 ${episode} / ${total}` : `#${item.rank}`}</em>
                              {tracked >= 0 && <i className="cover-progress"><i style={{ width: `${(episode / total) * 100}%` }} /></i>}
                            </span>
                            <h4>{item.title}</h4>
                            <small>{tracked >= 0 ? (episode === total ? "看过" : "在看") : `${item.votes} 人评分`}</small>
                          </article>
                        );
                      })}
                    </div>
                  </>
                ) : (
                  <>
                    <div className="segmented-outline" aria-hidden="true">
                      <span className="on"><Icon name="forum" size={18} />话题</span>
                      <span><Icon name="groups" size={18} />找小组</span>
                      <span><Icon name="feed" size={18} />全站动态</span>
                    </div>
                    <h3 className="subhead">热门小组</h3>
                    <div className="group-cards">
                      {hotGroups.map((group) => (
                        <div className="app-card group-card" key={group.name}>
                          <span className="round-avatar"><Icon name="groups" /></span>
                          <div><b>{group.name}</b><small>{group.meta}</small></div>
                        </div>
                      ))}
                    </div>
                    <div className="topic-list">
                      {topics.map((topic) => {
                        const read = readTopics.includes(topic.id);
                        return (
                          <button
                            type="button"
                            className={`app-card topic-card ${read ? "read" : ""}`}
                            aria-pressed={read}
                            onClick={() => setReadTopics((current) => current.includes(topic.id) ? current : [...current, topic.id])}
                            key={topic.id}
                          >
                            <span className="round-avatar small"><Icon name="personOn" size={16} /></span>
                            <div>
                              <b>{topic.title}</b>
                              <em>{topic.group}</em>
                              <small><Icon name="personOff" size={13} />小夏<Icon name="messageOff" size={13} />{topic.replies}<Icon name="schedule" size={13} />{read ? "已读" : "今天"}</small>
                            </div>
                            <Icon name="chevronRight" className="chev" />
                          </button>
                        );
                      })}
                    </div>
                  </>
                )}
              </>
            )}

            {activeTab === "message" && openChat === null && (
              <>
                <div className="title-row">
                  <h2 className="title-hub">消息</h2>
                  <span className="friends-link"><Icon name="people" />好友</span>
                </div>
                <div className="tab-bar icon-tabs" role="tablist">
                  <button type="button" role="tab" aria-selected={messageTab === "pm"} onClick={() => setMessageTab("pm")}><Icon name="forum" size={18} />私聊</button>
                  <button type="button" role="tab" aria-selected={messageTab === "groups"} onClick={() => setMessageTab("groups")}><Icon name="groups" size={18} />小组</button>
                  <button type="button" role="tab" aria-selected={messageTab === "notify"} onClick={() => setMessageTab("notify")}>
                    <span className="badge-host"><Icon name="notifications" size={18} /><i className="badge">3</i></span>通知
                  </button>
                </div>
                {messageTab === "pm" && (
                  <div className="row-list">
                    {conversations.map((conversation) => (
                      <button type="button" className="list-row" onClick={() => setOpenChat(conversation.id)} key={conversation.id}>
                        <span className="round-avatar blue">{conversation.avatar}</span>
                        <div><b>{conversation.name}</b><small>{conversation.id === 1 ? messages[messages.length - 1].text : conversation.last}</small></div>
                        <time>{conversation.time}</time>
                      </button>
                    ))}
                  </div>
                )}
                {messageTab === "groups" && (
                  <>
                    <div className="group-filter" aria-hidden="true"><span className="on">我的小组</span><span>管理的小组</span><span className="sort"><Icon name="filterList" size={18} />最新讨论</span></div>
                    <div className="row-list">
                      {[...hotGroups, { name: "音乐与日常", meta: "86 成员 · 32 话题" }].map((group) => (
                        <div className="list-row" key={group.name}>
                          <span className="round-avatar"><Icon name="groups" /></span>
                          <div><b>{group.name}</b><small>{group.meta.replace("成员", "位成员").replace("话题", "个讨论")}</small></div>
                          <Icon name="chevronRight" className="chev" />
                        </div>
                      ))}
                    </div>
                    <p className="end-note">已经到底了</p>
                  </>
                )}
                {messageTab === "notify" && (
                  <div className="row-list">
                    {notifications.map((item) => (
                      <div className="list-row notice" key={item.text}>
                        <span className="dot" />
                        <div><b>{item.text}</b><small>{item.time}</small></div>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}

            {activeTab === "message" && openChat !== null && (
              <div className="chat">
                <div className="chat-head">
                  <button type="button" className="icon-button" aria-label="返回消息列表" onClick={() => setOpenChat(null)}>
                    <svg className="mi" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M19 11H7.83l4.88-4.88a1 1 0 0 0-1.42-1.41l-6.59 6.58a1 1 0 0 0 0 1.41l6.59 6.59a1 1 0 1 0 1.41-1.41L7.83 13H19a1 1 0 0 0 0-2Z" /></svg>
                  </button>
                  <span className="round-avatar blue">{conversations.find((c) => c.id === openChat)?.avatar}</span>
                  <div><b>{conversations.find((c) => c.id === openChat)?.name}</b><small>{conversations.find((c) => c.id === openChat)?.note}</small></div>
                </div>
                <div className="chat-body">
                  {(openChat === 1 ? messages : [{ id: 1, mine: false, text: "新番表排好了，发你看看", time: "昨天 22:10" }]).map((message) => (
                    <div className={`bubble-row ${message.mine ? "mine" : ""}`} key={message.id}>
                      <time>{message.time}</time>
                      <p>{message.text}</p>
                    </div>
                  ))}
                </div>
                <small className="draft-note">草稿会自动保存在本机</small>
                <form className="chat-input" onSubmit={(event) => { event.preventDefault(); sendMessage(); }}>
                  <input aria-label="输入回复" placeholder="输入回复…" value={draft} onChange={(event) => setDraft(event.target.value)} maxLength={60} />
                  <button type="submit" disabled={!draft.trim()}>发送</button>
                </form>
              </div>
            )}

            {activeTab === "me" && (
              <div className="profile">
                <div className="profile-wash">
                  <div className="profile-top"><b>我的空间</b><span className="icon-button round" aria-hidden="true"><Icon name="settings" /></span></div>
                  <div className="profile-id">
                    <span className="big-avatar"><Icon name="personOn" size={30} /></span>
                    <div><h2>小沐</h2><small>@mubangumi_demo</small></div>
                  </div>
                  <p className="bio">记录喜欢的作品，也和朋友聊聊。</p>
                  <div className="stats"><span><b>{library.length}</b>收藏</span><span><b>{doing}</b>进行中</span><span><b>26</b>好友</span></div>
                </div>
                <div className="tab-bar icon-tabs stacked" aria-hidden="true">
                  <span className="on"><Icon name="messageOff" size={22} />我的动态</span>
                  <span><Icon name="people" size={22} />好友动态</span>
                  <span><Icon name="journal" size={22} />日志</span>
                </div>
                <article className="post timeline-post">
                  <div className="post-head"><span className="round-avatar small"><Icon name="personOn" size={16} /></span><b>小沐</b><Icon name="moreHoriz" className="post-more" /></div>
                  <p>周末留一点时间给喜欢的作品。<br />这次想慢慢看，也慢慢记录。</p>
                  <div className="post-foot">
                    <small>18 分钟前</small>
                    <button type="button" className={liked ? "liked" : ""} aria-pressed={liked} aria-label={liked ? "取消喜欢" : "喜欢"} onClick={() => setLiked((value) => !value)}>
                      <Icon name={liked ? "heartOn" : "heartOff"} size={22} />{liked ? 1 : ""}
                    </button>
                    <span><Icon name="comment" size={20} />2</span>
                  </div>
                </article>
                <span className="fab" aria-hidden="true"><Icon name="edit" /></span>
              </div>
            )}
          </div>

          {picker !== null && (
            <div className="sheet-scrim">
              <button type="button" className="scrim-close" tabIndex={-1} aria-hidden="true" onClick={() => setPicker(null)} />
              <div className="sheet" role="dialog" aria-label={`选择集数：${shows[picker].title}`}>
                <i className="sheet-handle" />
                <div className="sheet-head">
                  <b>{shows[picker].title}</b>
                  <button type="button" className="icon-button" aria-label="关闭选择集数" onClick={() => setPicker(null)}><Icon name="close" /></button>
                </div>
                <small className="muted">点格子记录看到哪一集，再点已看的格子可以撤回</small>
                <div className="episode-grid">
                  {Array.from({ length: shows[picker].total }, (_, index) => (
                    <button
                      type="button"
                      className={index < episodes[picker] ? "watched" : ""}
                      aria-label={`看到第 ${index + 1} 集`}
                      onClick={() => setEpisode(picker, index + 1 === episodes[picker] ? index : index + 1)}
                      key={index}
                    >{index + 1}</button>
                  ))}
                </div>
              </div>
            </div>
          )}

          <div className={`demo-toast ${toast ? "visible" : ""}`} role="status">{toast}</div>
        </div>

        <nav className="phone-nav" aria-label="演示导航">
          {tabs.map((tab) => (
            <button
              className={activeTab === tab.id ? "active" : ""}
              type="button"
              aria-label={tab.aria}
              aria-pressed={activeTab === tab.id}
              onClick={() => { setActiveTab(tab.id); setOpenChat(null); setStatusMenu(false); }}
              key={tab.id}
            >
              <span className="badge-host">
                <Icon name={activeTab === tab.id ? tab.on : tab.off} size={24} />
                {tab.id === "message" && <i className="badge">3</i>}
              </span>
              <span>{tab.label}</span>
            </button>
          ))}
        </nav>
      </div>
    </div>
  );
}
