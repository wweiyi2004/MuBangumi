"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";

const tabs = [
  { id: "home", label: "首页", icon: "⌂" },
  { id: "collection", label: "收藏", icon: "◇" },
  { id: "discover", label: "发现", icon: "⌕" },
  { id: "community", label: "社区", icon: "◌" },
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
  { title: "摇曳露营△", status: "想看", progress: "尚未开始", poster: "poster-c" },
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
  const [hasInteracted, setHasInteracted] = useState(false);
  const [selectedShow, setSelectedShow] = useState(0);
  const [episodes, setEpisodes] = useState(() => shows.map((show) => show.episode));
  const [syncVisible, setSyncVisible] = useState(false);
  const [collectionFilter, setCollectionFilter] = useState<CollectionFilter>("在看");
  const [discovery, setDiscovery] = useState<DiscoveryId>("trend");
  const [communityView, setCommunityView] = useState<"friends" | "topics">("friends");
  const [selectedTopic, setSelectedTopic] = useState<number | null>(null);
  const [likedPosts, setLikedPosts] = useState<number[]>([]);
  const syncTimer = useRef<number | null>(null);

  useEffect(() => {
    if (hasInteracted) return;
    const timer = window.setInterval(() => {
      setActiveTab((current) => {
        const currentIndex = tabs.findIndex((tab) => tab.id === current);
        return tabs[(currentIndex + 1) % tabs.length].id;
      });
    }, 5200);
    return () => window.clearInterval(timer);
  }, [hasInteracted]);

  useEffect(() => {
    return () => {
      if (syncTimer.current !== null) window.clearTimeout(syncTimer.current);
    };
  }, []);

  const interact = () => setHasInteracted(true);

  const selectTab = (tab: TabId) => {
    interact();
    setActiveTab(tab);
  };

  const markNextEpisode = () => {
    interact();
    setEpisodes((current) =>
      current.map((episode, index) =>
        index === selectedShow ? Math.min(episode + 1, shows[index].total) : episode,
      ),
    );
    setSyncVisible(true);
    if (syncTimer.current !== null) window.clearTimeout(syncTimer.current);
    syncTimer.current = window.setTimeout(() => setSyncVisible(false), 2600);
  };

  const toggleLike = (postId: number) => {
    interact();
    setLikedPosts((current) =>
      current.includes(postId)
        ? current.filter((id) => id !== postId)
        : [...current, postId],
    );
  };

  const currentShow = shows[selectedShow];
  const currentEpisode = episodes[selectedShow];
  const isComplete = currentEpisode === currentShow.total;
  const progress = `${Math.round((currentEpisode / currentShow.total) * 100)}%`;
  const visibleCollection = collectionItems.filter((item) => item.status === collectionFilter);
  const currentDiscovery = discoverySets[discovery];

  return (
    <div
      className="app-showcase"
      aria-label="可点击的 MuBangumi 产品演示"
    >
      <div className="showcase-orbit orbit-one" />
      <div className="showcase-orbit orbit-two" />
      <div className="demo-hint"><span>●</span> 可交互演示</div>
      <div className="app-window">
        <aside className="mock-sidebar" aria-label="演示导航">
          <Image src="/favicon.svg" alt="" width="34" height="34" />
          {tabs.map((tab) => (
            <button
              className={`mock-nav ${activeTab === tab.id ? "active" : ""}`}
              type="button"
              aria-label={`打开${tab.label}`}
              aria-pressed={activeTab === tab.id}
              onClick={() => selectTab(tab.id)}
              key={tab.id}
            >
              <span>{tab.icon}</span><b>{tab.label}</b>
            </button>
          ))}
          <div className="mock-avatar">M</div>
        </aside>

        <div className="mock-content">
          <div className="mock-topline">
            <span>{activeTab === "community" ? "社区有 3 条新动态" : "晚上好，Mori"}</span>
            <button type="button" aria-label="打开发现搜索" onClick={() => selectTab("discover")}>⌕</button>
          </div>

          <div className="demo-panel" key={activeTab} role="tabpanel" aria-live="polite">
            {activeTab === "home" && (
              <>
                <div className="mock-title-row">
                  <div><small>继续观看</small><h2>我的追番</h2></div>
                  <span className="mock-date">本季 · 12 部</span>
                </div>
                <div className="progress-card" key={currentShow.title}>
                  <div className={`poster poster-main ${currentShow.poster}`}><span>{currentShow.score}</span></div>
                  <div className="progress-copy">
                    <span className={`status-pill ${isComplete ? "complete" : ""}`}>{isComplete ? "已看完" : "正在追"}</span>
                    <h3>{currentShow.title}</h3>
                    <p>看到第 {currentEpisode} 话 · 共 {currentShow.total} 话</p>
                    <div className="progress-track"><span style={{ width: progress }} /></div>
                    <button type="button" onClick={markNextEpisode} disabled={isComplete}>
                      {isComplete ? "本季已看完" : "标记下一集"} <b>{isComplete ? "✓" : "→"}</b>
                    </button>
                  </div>
                </div>
                <div className="mock-section-title">
                  <b>本周放送</b>
                  <button type="button" onClick={() => selectTab("collection")}>查看全部</button>
                </div>
                <div className="poster-row">
                  {shows.map((show, index) => (
                    <button
                      type="button"
                      className={selectedShow === index ? "selected" : ""}
                      aria-pressed={selectedShow === index}
                      onClick={() => { interact(); setSelectedShow(index); }}
                      key={show.title}
                    >
                      <div className={`poster ${show.poster}`}><i>{episodes[index]}/{show.total}</i></div>
                      <span>{show.day}</span>
                    </button>
                  ))}
                </div>
              </>
            )}

            {activeTab === "collection" && (
              <>
                <div className="mock-title-row">
                  <div><small>全部收藏</small><h2>我的收藏</h2></div>
                  <span className="mock-date">共 146 部</span>
                </div>
                <div className="mock-filter-row" aria-label="收藏筛选">
                  {(["在看", "想看", "看过"] as CollectionFilter[]).map((filter) => (
                    <button
                      type="button"
                      className={collectionFilter === filter ? "active" : ""}
                      aria-pressed={collectionFilter === filter}
                      onClick={() => { interact(); setCollectionFilter(filter); }}
                      key={filter}
                    >{filter}</button>
                  ))}
                </div>
                <div className="collection-list">
                  {visibleCollection.map((item) => (
                    <button type="button" className="collection-row" onClick={() => selectTab("home")} key={item.title}>
                      <span className={`poster ${item.poster}`} />
                      <span><b>{item.title}</b><small>{item.progress}</small></span>
                      <i>›</i>
                    </button>
                  ))}
                </div>
                <div className="collection-summary">
                  <span><b>32</b><small>在看</small></span>
                  <span><b>48</b><small>想看</small></span>
                  <span><b>66</b><small>看过</small></span>
                </div>
              </>
            )}

            {activeTab === "discover" && (
              <>
                <div className="mock-title-row">
                  <div><small>找到下一部</small><h2>发现</h2></div>
                  <span className="mock-date">为你推荐</span>
                </div>
                <div className="discover-tabs" aria-label="推荐方式">
                  {(Object.keys(discoverySets) as DiscoveryId[]).map((id) => (
                    <button
                      type="button"
                      className={discovery === id ? "active" : ""}
                      aria-pressed={discovery === id}
                      onClick={() => { interact(); setDiscovery(id); }}
                      key={id}
                    >{discoverySets[id].label}</button>
                  ))}
                </div>
                <p className="discover-description">{currentDiscovery.description}</p>
                <div className="discover-grid" key={discovery}>
                  {currentDiscovery.items.map((item) => (
                    <button type="button" onClick={() => selectTab("home")} key={item.title}>
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
                  <span className="mock-date">实时更新</span>
                </div>
                <div className="community-tabs">
                  <button type="button" className={communityView === "friends" ? "active" : ""} onClick={() => { interact(); setCommunityView("friends"); }}>好友动态</button>
                  <button type="button" className={communityView === "topics" ? "active" : ""} onClick={() => { interact(); setCommunityView("topics"); }}>热门话题</button>
                </div>
                {communityView === "friends" ? (
                  <div className="timeline-list">
                    {posts.map((post) => {
                      const liked = likedPosts.includes(post.id);
                      return (
                        <article className="timeline-post" key={post.id}>
                          <span className="timeline-avatar">{post.avatar}</span>
                          <div>
                            <p><b>{post.name}</b><small>{post.time}</small></p>
                            <div>{post.text}</div>
                            <button
                              type="button"
                              className={liked ? "liked" : ""}
                              aria-pressed={liked}
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
                        onClick={() => { interact(); setSelectedTopic(topic.id); }}
                        key={topic.id}
                      >
                        <span>{topic.type}</span>
                        <div><b>{topic.title}</b><small>{selectedTopic === topic.id ? "已打开话题预览" : topic.meta}</small></div>
                        <i>{selectedTopic === topic.id ? "✓" : "›"}</i>
                      </button>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      </div>

      <div className={`floating-card floating-sync ${syncVisible ? "visible" : ""}`} role="status">
        <span className="float-icon">✓</span>
        <div><b>进度已同步</b><small>{currentShow.title} · 第 {currentEpisode} 话</small></div>
      </div>
      <div className="floating-card floating-score">
        <small>{activeTab === "community" ? "今日社区动态" : "当前条目评分"}</small>
        <b>{activeTab === "community" ? "28" : currentShow.score}<sup>{activeTab === "community" ? "条" : ""}</sup></b>
      </div>
      <div className="demo-pagination" aria-hidden="true">
        {tabs.map((tab) => <i className={activeTab === tab.id ? "active" : ""} key={tab.id} />)}
      </div>
    </div>
  );
}
