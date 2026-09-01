import { Icon } from "./icons";
import type { Post, SessionUser } from "../types/forum";
import { compactCount } from "../lib/format";

export function DiscoveryRail({ posts, user, onLogin }: { posts: Post[]; user: SessionUser | null; onLogin: () => void }) {
  const topics = posts.slice(0, 5);
  const ranking = posts
    .slice()
    .sort((a, b) => b.commentCount + b.likeCount - (a.commentCount + a.likeCount))
    .slice(0, 5);

  return (
    <aside className="discovery-rail" aria-label="社区发现">
      <section className="discovery-panel">
        <div className="discovery-heading"><h2>热门话题</h2><button type="button">更多 <Icon name="chevron-right" size={15} /></button></div>
        <div className="topic-list">
          {topics.length ? topics.map((post, index) => (
            <div className="topic-row" key={post.id}>
              <span className={`topic-index tone-${index % 3}`}>#</span>
              <span className="topic-title">{post.title}</span>
              <span className="topic-count">{compactCount(post.commentCount + post.likeCount)}<small>热度</small></span>
            </div>
          )) : <p className="empty-rail">暂时还没有热门内容</p>}
        </div>
      </section>

      <section className="discovery-panel ranking-panel">
        <div className="discovery-heading"><h2>本周榜单</h2><button type="button">更多 <Icon name="chevron-right" size={15} /></button></div>
        <div className="ranking-list">
          {ranking.length ? ranking.map((post, index) => (
            <div className="ranking-row" key={post.id}>
              <span className={`rank-number rank-${index + 1}`}>{index + 1}</span>
              <span className="ranking-avatar"><span>{post.author.nickname.slice(-1)}</span></span>
              <span className="ranking-name">{post.author.nickname}</span>
              <span className="level-label">Lv.{post.author.level || 1}</span>
            </div>
          )) : <p className="empty-rail">登录后查看榜单</p>}
        </div>
      </section>

      <section className="checkin-panel">
        <div className="discovery-heading"><h2>签到积分</h2><button type="button">规则 <Icon name="chevron-right" size={15} /></button></div>
        <div className="checkin-body">
          <div>
            <strong>{user ? "今天来过" : "登录后签到"}</strong>
            <p>{user ? "签到可获得社区积分" : "登录后开启每日签到"}</p>
          </div>
          <span className="checkin-icon"><Icon name="trophy" size={38} /></span>
        </div>
        <button type="button" className="checkin-button" onClick={onLogin}>{user ? "今日签到" : "去登录"}</button>
      </section>
    </aside>
  );
}
