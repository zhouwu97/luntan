import { SiteHeader } from "../../../components/site-header";
import { Icon } from "../../../components/icons";

export default function PostLoading() {
  return (
    <>
      <SiteHeader />

      {/* 移动端顶部标题骨架 */}
      <header className="detail-head mobile-only">
        <span className="icon-btn" style={{ opacity: 0.5 }}>
          <Icon name="chevron-left" size={22} />
        </span>
        <span className="detail-community-name" style={{ width: 80, height: 16, background: "var(--line, #e2e8f0)", borderRadius: 4, display: "inline-block" }} />
        <span className="icon-btn" style={{ opacity: 0.5 }}>
          <Icon name="more" size={18} />
        </span>
      </header>

      <main className="page-frame post-detail-page-frame">
        <div className="detail-grid">
          <section className="detail-main">
            <div className="back-link detail-back desktop-only" style={{ opacity: 0.6 }}>
              <Icon name="chevron-left" size={17} />
              <span>正在进入讨论…</span>
            </div>

            <article className="detail-article" style={{ pointerEvents: "none" }}>
              <header className="detail-author">
                <div className="avatar avatar-large" style={{ background: "linear-gradient(110deg, #f1f5f9 8%, #e2e8f0 18%, #f1f5f9 33%)", backgroundSize: "200% 100%", animation: "shimmer 1.5s infinite" }} />
                <div className="post-author" style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                  <div style={{ width: 120, height: 16, background: "#e2e8f0", borderRadius: 4, animation: "shimmer 1.5s infinite" }} />
                  <div style={{ width: 90, height: 12, background: "#f1f5f9", borderRadius: 4 }} />
                </div>
              </header>

              <div style={{ width: "75%", height: 28, background: "#e2e8f0", borderRadius: 6, margin: "18px 0 14px", animation: "shimmer 1.5s infinite" }} />

              <div className="detail-body" style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                <div style={{ width: "100%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                <div style={{ width: "96%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                <div style={{ width: "88%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                <div style={{ width: "60%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
              </div>

              <div className="detail-stats" style={{ marginTop: 24, opacity: 0.5 }}>
                <span style={{ width: 60, height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                <span style={{ width: 60, height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                <span style={{ width: 60, height: 16, background: "#f1f5f9", borderRadius: 4 }} />
              </div>
            </article>

            {/* 评论区占位骨架 */}
            <section className="detail-comments" style={{ marginTop: 20 }}>
              <div style={{ width: 100, height: 20, background: "#e2e8f0", borderRadius: 4, marginBottom: 16 }} />
              <div className="detail-skeleton" style={{ gap: 12 }}>
                <div style={{ height: 100, borderRadius: 12 }} />
                <div style={{ height: 100, borderRadius: 12 }} />
              </div>
            </section>
          </section>

          {/* 桌面端侧边栏骨架 */}
          <aside className="detail-aside desktop-only">
            <section className="aside-panel" style={{ height: 180, animation: "shimmer 1.5s infinite" }} />
            <section className="aside-panel" style={{ height: 220, animation: "shimmer 1.5s infinite" }} />
          </aside>
        </div>
      </main>
    </>
  );
}
