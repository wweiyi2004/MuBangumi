"use client";

import { useEffect, useRef, useState } from "react";

const tabs = [
  { id: "home", label: "首页", icon: "M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5h-5v5H5a1 1 0 0 1-1-1v-8.5Z" },
  { id: "collection", label: "收藏", icon: "M6 4h12v16l-6-4-6 4V4Z" },
  { id: "discover", label: "发现", icon: "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14Zm9 16-4-4" },
  { id: "community", label: "社区", icon: "M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9l-5 3V6Z" },
] as const;

type TabId = (typeof tabs)[number]["id"];

const shows = [
  { title: "葬送的芙莉莲", episode: 24, total: 28, day: "周一", score: "9.1", poster: "poster-a" },
  { title: "迷宫饭", episode: 18, total: 24, day: "周三", score: "8.4", poster: "poster-b" },
  { title: "跃动青春", episode: 9, total: 12, day: "周五", score: "8.2", poster: "poster-c" },
  { title: "宝石之国", episode: 6, total: 12, day: "周日", score: "8.7", poster: "poster-d" },
] as const;

const collectionItems = [
  { title: "葬送的芙莉莲", status: "在看", progress: "24 / 28", poster: "poster-a" },
  { title: "迷宫饭", status: "在看", progress: "18 / 24", poster: "poster-b" },
  { title: "跃动青春", status: "在看", progress: "9 / 12", poster: "poster-c" },
  { title: "宝石之国", status: "在看", progress: "6 / 12", poster: "poster-d" },
  { title: "摇曳露营△", status: "想看", progress: "尚未开始", poster: "poster-c" },
  { title: "少女终末旅行", status: "想看", progress: "尚未开始", poster: "poster-a" },
  { title: "四叠半神话大系", status: "看过", progress: "11 / 11", poster: "poster-d" },
] as const;

const discoverySets = {
  trend: {
    label: "口碑上升",
    description: "最近 30 天评分持续上涨",
    items: [
      { title: "少女终末旅行", score: "8.7", change: "+0.3", poster: "poster-c" },
      { title: "冰菓", score: "8.3", change: "+0.2", poster: "poster-b" },
      { title: "来自深渊", score: "8.6", change: "+0.2", poster: "poster-d" },
    ],
  },
  season: {
    label: "本季新番",
    description: "从本季高热度条目中精选",
    items: [
      { title: "夏日放送", score: "8.1", change: "新作", poster: "poster-a" },
      { title: "星海来信", score: "7.9", change: "新作", poster: "poster-c" },
      { title: "雨后车站", score: "7.8", change: "新作", poster: "poster-b" },
    ],
  },
  friends: {
    label: "好友在看",
    description: "8 位好友最近收藏了这些作品",
    items: [
      { title: "跃动青春", score: "8.2", change: "6 人", poster: "poster-c" },
      { title: "迷宫饭", score: "8.4", change: "5 人", poster: "poster-b" },
      { title: "宝石之国", score: "8.7", change: "4 人", poster: "poster-d" },
    ],
  },
} as const;

type DiscoveryId = keyof typeof discoverySets;
type CollectionFilter = "在看" | "想看" | "看过";

const posts = [
  { id: 1, avatar: "澄", name: "透明澄", time: "8 分钟前", text: "补完了最后两话，收束得比想象中温柔。", likes: 18 },
  { id: 2, avatar: "M", name: "Mori", time: "23 分钟前", text: "本季新番表终于排好了，周五又要看不过来了。", likes: 11 },
] as const;

const topics = [
  { id: 1, type: "动画", title: "这一季最惊喜的演出是哪一话？", meta: "42 回复 · 刚刚更新" },
  { id: 2, type: "音乐", title: "分享最近循环的动画原声", meta: "28 回复 · 12 分钟前" },
  { id: 3, type: "闲聊", title: "你的第一部深夜动画是什么？", meta: "76 回复 · 30 分钟前" },
] as const;

export function ProductDemo() {
  const [activeTab, setActiveTab] = useState<TabId>("home");
  const [selectedShow, setSelectedShow] = useState(0);
  const [episodes, setEpisodes] = useState<number[]>(() => shows.map((show) => show.episode));
  const [toast, setToast] = useState<{ title: string; episode: number } | null>(null);
  const [collectionFilter, setCollectionFilter] = useState<CollectionFilter>("在看");
  const [discovery, setDiscovery] = useState<DiscoveryId>("trend");
  const [communityView, setCommunityView] = useState<"friends" | "topics">("friends");
  const [selectedTopic, setSelectedTopic] = useState<number | null>(null);
  const [likedPosts, setLikedPosts] = useState<number[]>([]);
  const toastTimer = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    };
  }, []);

  const setEpisode = (episode: number) => {
    const show = shows[selectedShow];
    const next = Math.max(0, Math.min(episode, show.total));
    setEpisodes((current) => current.map((value, index) => (index === selectedShow ? next : value)));
    setToast({ title: show.title, episode: next });
    if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 2400);
  };

  const markNextEpisode = () => setEpisode(episodes[selectedShow] + 1);

  const toggleLike = (postId: number) => {
    setLikedPosts((current) =>
      current.includes(postId)
        ? current.filter((id) => id !== postId)
        : [...current, postId],
    );
  };

  const currentShow = shows[selectedShow];
  const currentEpisode = episodes[selectedShow];
  const isComplete = currentEpisode === currentShow.total;
  const demoCollection = collectionItems.map((item) => {
    const index = shows.findIndex((show) => show.title === item.title);
    if (index < 0) return item;
    return {
      ...item,
      status: episodes[index] === shows[index].total ? "看过" : "在看",
      progress: `${episodes[index]} / ${shows[index].total}`,
    };
  });
  const visibleCollection = demoCollection.filter((item) => item.status === collectionFilter);
  const currentDiscovery = discoverySets[discovery];

  return (
    <div className="app-showcase" aria-label="可点击的 MuBangumi 产品演示">
      <div className="demo-hint"><span /> 可交互演示 · 示例数据</div>
      <div className="phone">
        <div className="phone-status" aria-hidden="true"><b>21:24</b><span /></div>
        <div className="phone-screen">
          <div className="demo-panel" key={activeTab} role="tabpanel" aria-live="polite">
            {activeTab === "home" && (
              <>
                <div className="mock-title-row">
                  <div><small>晚上好，Mori</small><h2>我的追番</h2></div>
                  <span className="mock-chip">本季 12 部</span>
                </div>
                <div className="progress-card" key={currentShow.title}>
                  <div className="progress-head">
                    <div className={`poster ${currentShow.poster}`}><span>{currentShow.score}</span></div>
                    <div className="progress-copy">
                      <span className={`status-pill ${isComplete ? "complete" : ""}`}>{isComplete ? "已看完" : `${currentShow.day}更新`}</span>
                      <h3>{currentShow.title}</h3>
                      <p>看到第 {currentEpisode} 话 · 共 {currentShow.total} 话</p>
                    </div>
                  </div>
                  <div className="episode-grid" role="group" aria-label="章节格子">
                    {Array.from({ length: currentShow.total }, (_, index) => (
                      <button
                        type="button"
                        className={index < currentEpisode ? "watched" : index === currentEpisode ? "next" : ""}
                        aria-label={`看到第 ${index + 1} 话`}
                        onClick={() => setEpisode(index + 1)}
                        key={index}
                      >{index + 1}</button>
                    ))}
                  </div>
                  <button type="button" className="mark-next" onClick={markNextEpisode} disabled={isComplete}>
                    {isComplete ? "本季已看完 ✓" : `标记下一集 · 第 ${currentEpisode + 1} 话`}
                  </button>
                </div>
                <div className="mock-section-title">
                  <b>本周放送</b>
                  <button type="button" onClick={() => setActiveTab("collection")}>全部</button>
                </div>
                <div className="poster-row">
                  {shows.map((show, index) => (
                    <button
                      type="button"
                      className={selectedShow === index ? "selected" : ""}
                      aria-pressed={selectedShow === index}
                      aria-label={`${show.title}，${show.day}`}
                      onClick={() => setSelectedShow(index)}
                      key={show.title}
                    >
                      <span className={`poster ${show.poster}`}><i>{episodes[index]}/{show.total}</i></span>
                      <span>{show.day}</span>
                    </button>
                  ))}
                </div>
              </>
            )}

            {activeTab === "collection" && (
              <>
                <div className="mock-title-row">
                  <div><small>演示收藏 · {demoCollection.length} 部</small><h2>我的收藏</h2></div>
                </div>
                <div className="segmented" aria-label="收藏筛选">
                  {(["在看", "想看", "看过"] as CollectionFilter[]).map((filter) => (
                    <button
                      type="button"
                      className={collectionFilter === filter ? "active" : ""}
                      aria-pressed={collectionFilter === filter}
                      onClick={() => setCollectionFilter(filter)}
                      key={filter}
                    >{filter}<small aria-hidden="true">{demoCollection.filter((item) => item.status === filter).length}</small></button>
                  ))}
                </div>
                <div className="collection-list">
                  {visibleCollection.map((item) => (
                    <button type="button" className="collection-row" onClick={() => setActiveTab("home")} key={item.title}>
                      <span className={`poster ${item.poster}`} />
                      <span><b>{item.title}</b><small>{item.progress}</small></span>
                      <i aria-hidden="true">›</i>
                    </button>
                  ))}
                </div>
              </>
            )}

            {activeTab === "discover" && (
              <>
                <div className="mock-title-row">
                  <div><small>找到下一部</small><h2>发现</h2></div>
                </div>
                <div className="segmented" aria-label="推荐方式">
                  {(Object.keys(discoverySets) as DiscoveryId[]).map((id) => (
                    <button
                      type="button"
                      className={discovery === id ? "active" : ""}
                      aria-pressed={discovery === id}
                      onClick={() => setDiscovery(id)}
                      key={id}
                    >{discoverySets[id].label}</button>
                  ))}
                </div>
                <p className="discover-description">{currentDiscovery.description}</p>
                <div className="discover-grid" key={discovery}>
                  {currentDiscovery.items.map((item) => (
                    <button type="button" onClick={() => setActiveTab("home")} key={item.title}>
                      <span className={`poster ${item.poster}`}><i>{item.change}</i></span>
                      <b>{item.title}</b>
                      <small><em>★</em> {item.score}</small>
                    </button>
                  ))}
                </div>
              </>
            )}

            {activeTab === "community" && (
              <>
                <div className="mock-title-row">
                  <div><small>好友与社区</small><h2>时间线</h2></div>
                </div>
                <div className="segmented">
                  <button type="button" aria-pressed={communityView === "friends"} className={communityView === "friends" ? "active" : ""} onClick={() => setCommunityView("friends")}>好友动态</button>
                  <button type="button" aria-pressed={communityView === "topics"} className={communityView === "topics" ? "active" : ""} onClick={() => setCommunityView("topics")}>热门话题</button>
                </div>
                {communityView === "friends" ? (
                  <div className="timeline-list">
                    {posts.map((post) => {
                      const liked = likedPosts.includes(post.id);
                      return (
                        <article className="timeline-post" key={post.id}>
                          <span className="timeline-avatar" aria-hidden="true">{post.avatar}</span>
                          <div>
                            <p><b>{post.name}</b><small>{post.time}</small></p>
                            <div>{post.text}</div>
                            <button
                              type="button"
                              className={liked ? "liked" : ""}
                              aria-pressed={liked}
                              aria-label={`贴贴，${post.likes + (liked ? 1 : 0)} 人`}
                              onClick={() => toggleLike(post.id)}
                            >{liked ? "♥" : "♡"} {post.likes + (liked ? 1 : 0)}</button>
                          </div>
                        </article>
                      );
                    })}
                  </div>
                ) : (
                  <div className="topic-list">
                    {topics.map((topic) => (
                      <button
                        type="button"
                        className={selectedTopic === topic.id ? "selected" : ""}
                        aria-pressed={selectedTopic === topic.id}
                        onClick={() => setSelectedTopic(topic.id)}
                        key={topic.id}
                      >
                        <span>{topic.type}</span>
                        <div><b>{topic.title}</b><small>{selectedTopic === topic.id ? "已打开话题预览" : topic.meta}</small></div>
                        <i aria-hidden="true">{selectedTopic === topic.id ? "✓" : "›"}</i>
                      </button>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>

          <div className={`demo-toast ${toast ? "visible" : ""}`} role="status">
            {toast && <><b>✓</b> {toast.title} · 看到第 {toast.episode} 话</>}
          </div>
        </div>

        <nav className="phone-nav" aria-label="演示导航">
          {tabs.map((tab) => (
            <button
              className={activeTab === tab.id ? "active" : ""}
              type="button"
              aria-label={`打开${tab.label}`}
              aria-pressed={activeTab === tab.id}
              onClick={() => setActiveTab(tab.id)}
              key={tab.id}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d={tab.icon} /></svg>
              <span>{tab.label}</span>
            </button>
          ))}
        </nav>
      </div>

      <div className="floating-card floating-score" aria-hidden="true">
        <small>当前条目评分</small>
        <b>{currentShow.score}</b>
        <span className="mini-stars">★★★★★</span>
      </div>
      <div className="floating-card floating-heat" aria-hidden="true">
        <small>本周打卡</small>
        <span className="heat-row">
          {[3, 1, 0, 2, 4, 1, 2].map((level, index) => <i className={`h${level}`} key={index} />)}
        </span>
      </div>
    </div>
  );
}
