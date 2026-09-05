"use client";

import Link from "next/link";
import { FormEvent, useEffect, useRef, useState } from "react";
import { Icon } from "../../../components/icons";
import { SiteHeader } from "../../../components/site-header";
import { useSession } from "../../../components/session-provider";
import { useToast } from "../../../components/toast-context";
import {
  getHomeRecommendations,
  getPost,
  removeHomeRecommendation,
  reorderHomeRecommendations,
  searchForum,
  setHomeRecommendation,
} from "../../../lib/api/forum";
import { formatError, relativeTime } from "../../../lib/format";
import type { HomeRecommendationItem, Post } from "../../../types/forum";

function formatDay(value?: string): string {
  if (!value) return "永久";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "永久"
    : new Intl.DateTimeFormat("zh-CN", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
      }).format(date);
}

export default function AdminRecommendationsPage() {
  const { user, ready } = useSession();
  const { showToast } = useToast();
  const isModerator = Boolean(
    user?.capabilities?.can_manage_admins ||
    user?.capabilities?.can_moderate ||
    user?.role === "admin" ||
    user?.role === "super_admin" ||
    user?.role === "moderator"
  );

  const [items, setItems] = useState<HomeRecommendationItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  // 搜索新帖子加入推荐
  const [searchQuery, setSearchQuery] = useState("");
  const [searching, setSearching] = useState(false);
  const [searchCandidates, setSearchCandidates] = useState<Post[]>([]);
  const [targetPost, setTargetPost] = useState<Post | null>(null);
  const [targetPosition, setTargetPosition] = useState(1);
  const [targetExpiresAt, setTargetExpiresAt] = useState("");
  const [adding, setAdding] = useState(false);

  const dragIndex = useRef<number | null>(null);

  const loadRecommendations = async () => {
    setLoading(true);
    setError("");
    try {
      const list = await getHomeRecommendations();
      setItems(list);
      setDirty(false);
      setTargetPosition(list.length + 1);
    } catch (requestError) {
      setError(formatError(requestError, "推荐列表暂时无法加载"));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!isModerator) return;
    void loadRecommendations();
  }, [isModerator]);

  async function handleSearchPosts(e: FormEvent) {
    e.preventDefault();
    const query = searchQuery.trim();
    if (!query) return;
    setSearching(true);
    setSearchCandidates([]);
    setTargetPost(null);
    try {
      // 如果看起来像具体 post ID，先尝试直接查单帖
      if (query.startsWith("post-") || query.length >= 10) {
        try {
          const single = await getPost(query);
          if (single?.id) {
            setSearchCandidates([single]);
            setTargetPost(single);
            setSearching(false);
            return;
          }
        } catch {
          // 忽略单帖查不到，继续走搜索
        }
      }
      const searchRes = await searchForum(query);
      const postCandidates: Post[] = await Promise.all(
        searchRes.posts.slice(0, 10).map((p) => getPost(p.id).catch(() => null))
      ).then((arr) => arr.filter((it): it is Post => Boolean(it)));
      setSearchCandidates(postCandidates);
      if (postCandidates.length > 0) {
        setTargetPost(postCandidates[0]);
      } else {
        showToast("未找到匹配的公开帖子");
      }
    } catch (searchErr) {
      showToast(formatError(searchErr, "搜索帖子失败，请重试"));
    } finally {
      setSearching(false);
    }
  }

  async function handleAddRecommendation(e: FormEvent) {
    e.preventDefault();
    if (!targetPost) return;
    setAdding(true);
    try {
      const expiresAtIso = targetExpiresAt ? new Date(targetExpiresAt).toISOString() : undefined;
      await setHomeRecommendation(targetPost.id, {
        position: targetPosition,
        expiresAt: expiresAtIso,
      });
      showToast("已成功加入首页推荐！");
      setTargetPost(null);
      setSearchCandidates([]);
      setSearchQuery("");
      setTargetExpiresAt("");
      await loadRecommendations();
    } catch (addErr) {
      showToast(formatError(addErr, "加入推荐失败"));
    } finally {
      setAdding(false);
    }
  }

  async function handleRemove(postId: string) {
    if (!window.confirm("确定要将此帖子从首页推荐中移除吗？")) return;
    try {
      await removeHomeRecommendation(postId);
      showToast("已从首页推荐中移除");
      setItems((curr) => curr.filter((it) => it.postId !== postId));
      setDirty(false);
    } catch (removeErr) {
      showToast(formatError(removeErr, "移除失败，请重试"));
    }
  }

  function moveItem(from: number, to: number) {
    if (to < 0 || to >= items.length) return;
    const next = [...items];
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    setItems(next);
    setDirty(true);
    setNotice("排序已修改，点击上方【保存排序】即可向全站生效。");
  }

  async function handleSaveOrder() {
    if (saving || items.length === 0) return;
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const orderPayload = items.map((it, idx) => ({
        postId: it.postId,
        position: idx + 1,
      }));
      await reorderHomeRecommendations(orderPayload);
      showToast("首页推荐排序已保存");
      setDirty(false);
      await loadRecommendations();
    } catch (saveErr) {
      setError(formatError(saveErr, "保存推荐排序失败"));
    } finally {
      setSaving(false);
    }
  }

  if (!ready) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <div className="loading-stack" style={{ padding: 40, textAlign: "center", color: "#64748b" }}>
            <Icon name="sparkle" size={24} />
            <p>正在验证管理员权限…</p>
          </div>
        </main>
      </>
    );
  }

  if (!isModerator) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <div className="empty-state">
            <Icon name="lock" size={32} />
            <h1>访问受限</h1>
            <p>该功能仅限平台管理员使用。</p>
            <Link href="/" className="primary-link">返回首页</Link>
          </div>
        </main>
      </>
    );
  }

  return (
    <>
      <SiteHeader />
      <main className="page-frame admin-page-frame">
        <header className="admin-header">
          <div className="admin-header-title">
            <span className="admin-badge">
              <Icon name="sparkle" size={14} /> 管理后台
            </span>
            <h1>首页人工推荐管理</h1>
            <p>
              管理「推荐」板块展示的精选帖子与排列位次。
              严格仅展示管理员人工推荐的内容，不自动补热门，无推荐时呈现标准空状态。
            </p>
          </div>

          <div className="admin-subnav" role="tablist">
            <Link href="/admin/ranking" className="admin-subnav-link">
              <Icon name="trophy" size={16} /> 排行榜排序
            </Link>
            <Link href="/admin/recommendations" className="admin-subnav-link active">
              <Icon name="sparkle" size={16} /> 首页推荐精选
            </Link>
          </div>
        </header>

        {error && <div className="data-note" role="alert" style={{ borderColor: "#fca5a5", color: "#dc2626" }}>{error}</div>}
        {notice && <div className="data-note" role="status" style={{ borderColor: "#bfdbfe", color: "#2563eb" }}>{notice}</div>}

        {/* 搜索添加推荐面板 */}
        <section className="card admin-search-panel" style={{ padding: 18, marginBottom: 20 }}>
          <h3 style={{ margin: "0 0 12px", fontSize: 16, display: "flex", alignItems: "center", gap: 8 }}>
            <Icon name="search" size={16} /> 添加推荐帖子
          </h3>
          <form onSubmit={handleSearchPosts} style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <input
              type="text"
              className="text-input"
              style={{ flex: "1 1 320px", height: 40, border: "1px solid #dfe8f2", borderRadius: 10, padding: "0 12px" }}
              placeholder="搜索帖子：标题 / 用户昵称 / 帖子 ID..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
            <button
              type="submit"
              className="primary-button"
              disabled={searching || !searchQuery.trim()}
              style={{ height: 40, padding: "0 20px" }}
            >
              {searching ? "搜索中…" : "搜索帖子"}
            </button>
          </form>

          {/* 候选列表 */}
          {searchCandidates.length > 0 && (
            <div style={{ marginTop: 16, borderTop: "1px solid #edf2f7", paddingTop: 14 }}>
              <div style={{ fontSize: 13, color: "#64748b", marginBottom: 8 }}>请选择要推荐的帖子：</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                {searchCandidates.map((cand) => (
                  <div
                    key={cand.id}
                    onClick={() => setTargetPost(cand)}
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      padding: "10px 14px",
                      borderRadius: 10,
                      border: targetPost?.id === cand.id ? "2px solid #3b82f6" : "1px solid #e2e8f0",
                      background: targetPost?.id === cand.id ? "#eff6ff" : "#fff",
                      cursor: "pointer",
                    }}
                  >
                    <div>
                      <strong style={{ fontSize: 14, color: "#1e293b" }}>{cand.title}</strong>
                      <div style={{ fontSize: 12, color: "#64748b", marginTop: 2 }}>
                        {cand.author.nickname} · {cand.community.name} · {relativeTime(cand.createdAt)} · ID: {cand.id}
                      </div>
                    </div>
                    {targetPost?.id === cand.id ? (
                      <span style={{ fontSize: 12, color: "#3b82f6", fontWeight: 700 }}>已选中</span>
                    ) : (
                      <span style={{ fontSize: 12, color: "#94a3b8" }}>点击选择</span>
                    )}
                  </div>
                ))}
              </div>

              {targetPost && (
                <form
                  onSubmit={handleAddRecommendation}
                  style={{
                    display: "flex",
                    gap: 12,
                    alignItems: "center",
                    flexWrap: "wrap",
                    marginTop: 14,
                    padding: 14,
                    background: "#f8fafc",
                    borderRadius: 10,
                  }}
                >
                  <label style={{ display: "inline-flex", alignItems: "center", gap: 6, fontSize: 13 }}>
                    <span>推荐位次：</span>
                    <input
                      type="number"
                      min={1}
                      value={targetPosition}
                      onChange={(e) => setTargetPosition(Math.max(1, Number(e.target.value) || 1))}
                      style={{ width: 70, height: 34, border: "1px solid #cbd5e1", borderRadius: 8, padding: "0 8px" }}
                    />
                  </label>

                  <label style={{ display: "inline-flex", alignItems: "center", gap: 6, fontSize: 13 }}>
                    <span>过期时间 (可选)：</span>
                    <input
                      type="datetime-local"
                      value={targetExpiresAt}
                      onChange={(e) => setTargetExpiresAt(e.target.value)}
                      style={{ height: 34, border: "1px solid #cbd5e1", borderRadius: 8, padding: "0 8px" }}
                    />
                  </label>

                  <button
                    type="submit"
                    className="primary-button"
                    disabled={adding}
                    style={{ height: 36, padding: "0 18px", marginLeft: "auto" }}
                  >
                    {adding ? "正在提交…" : "确认加入首页推荐"}
                  </button>
                </form>
              )}
            </div>
          )}
        </section>

        {/* 当前推荐列表面板 */}
        <section className="card admin-list-panel" style={{ padding: 18 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
            <div>
              <h2 style={{ margin: 0, fontSize: 18, display: "flex", alignItems: "center", gap: 8 }}>
                <Icon name="flame" size={18} /> 当前推荐列表 ({items.length} 篇)
              </h2>
              <p style={{ margin: "4px 0 0", color: "#64748b", fontSize: 13 }}>
                按位次正序（position ASC）在首页推荐展示。支持上下移动与拖拽调整。
              </p>
            </div>

            <div style={{ display: "flex", gap: 10 }}>
              <button
                type="button"
                className="primary-button"
                disabled={!dirty || saving}
                onClick={handleSaveOrder}
                style={{ height: 38, padding: "0 18px" }}
              >
                {saving ? "保存中…" : "保存排序"}
              </button>
            </div>
          </div>

          {loading ? (
            <div className="loading-stack" style={{ padding: "20px 0" }}>
              <div className="skeleton-card short" />
            </div>
          ) : items.length === 0 ? (
            <div className="empty-state" style={{ padding: "40px 20px" }}>
              <Icon name="sparkle" size={28} />
              <h2>暂无人工推荐内容</h2>
              <p>在上方搜索帖子并加入推荐，被推荐的帖子将立即展示在首页「推荐」板块中。</p>
            </div>
          ) : (
            <div className="admin-rec-table" style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              {items.map((item, index) => {
                const post = item.post;
                const isFirst = index === 0;
                const isLast = index === items.length - 1;

                return (
                  <div
                    key={item.postId}
                    draggable
                    onDragStart={() => {
                      dragIndex.current = index;
                    }}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={() => {
                      if (dragIndex.current !== null && dragIndex.current !== index) {
                        moveItem(dragIndex.current, index);
                      }
                      dragIndex.current = null;
                    }}
                    style={{
                      display: "grid",
                      gridTemplateColumns: "36px 40px minmax(0, 1fr) 140px 140px 80px",
                      alignItems: "center",
                      gap: 12,
                      padding: "12px 14px",
                      border: "1px solid #e2e8f0",
                      borderRadius: 12,
                      background: "#fff",
                      transition: "all 0.15s ease",
                    }}
                  >
                    {/* 拖拽手柄 */}
                    <div
                      style={{ cursor: "grab", color: "#94a3b8", display: "grid", placeItems: "center", fontSize: 18 }}
                      title="拖拽排序"
                    >
                      ☰
                    </div>

                    {/* 序号 */}
                    <div style={{ fontWeight: 800, color: "#3b82f6", textAlign: "center", fontSize: 15 }}>
                      #{index + 1}
                    </div>

                    {/* 帖子信息 */}
                    <div style={{ minWidth: 0 }}>
                      <Link
                        href={`/post/${encodeURIComponent(item.postId)}`}
                        target="_blank"
                        style={{ fontWeight: 700, fontSize: 14, color: "#1e293b", textDecoration: "none" }}
                      >
                        {post?.title || `[帖子 ID: ${item.postId}]`}
                      </Link>
                      <div style={{ fontSize: 12, color: "#64748b", marginTop: 3 }}>
                        作者: {post?.author?.nickname || "—"} · 板块: {post?.community?.name || "—"}
                        {!post && (
                          <span style={{ color: "#ef4444", marginLeft: 8, fontWeight: 700 }}>
                            (帖子可能已删除或隐藏)
                          </span>
                        )}
                      </div>
                    </div>

                    {/* 推荐时间 */}
                    <div style={{ fontSize: 12, color: "#64748b" }}>
                      <div>推荐于:</div>
                      <div>{relativeTime(item.recommendedAt)}</div>
                    </div>

                    {/* 过期时间 */}
                    <div style={{ fontSize: 12, color: item.expiresAt ? "#d97706" : "#10b981" }}>
                      <div>有效期:</div>
                      <div>{formatDay(item.expiresAt)}</div>
                    </div>

                    {/* 操作 */}
                    <div style={{ display: "flex", alignItems: "center", gap: 6, justifyContent: "flex-end" }}>
                      <button
                        type="button"
                        disabled={isFirst}
                        onClick={() => moveItem(index, index - 1)}
                        style={{
                          width: 26,
                          height: 26,
                          borderRadius: 6,
                          border: "1px solid #cbd5e1",
                          background: "#fff",
                          cursor: isFirst ? "not-allowed" : "pointer",
                          opacity: isFirst ? 0.4 : 1,
                        }}
                        title="上移"
                      >
                        ↑
                      </button>
                      <button
                        type="button"
                        disabled={isLast}
                        onClick={() => moveItem(index, index + 1)}
                        style={{
                          width: 26,
                          height: 26,
                          borderRadius: 6,
                          border: "1px solid #cbd5e1",
                          background: "#fff",
                          cursor: isLast ? "not-allowed" : "pointer",
                          opacity: isLast ? 0.4 : 1,
                        }}
                        title="下移"
                      >
                        ↓
                      </button>
                      <button
                        type="button"
                        onClick={() => handleRemove(item.postId)}
                        style={{
                          padding: "4px 8px",
                          borderRadius: 6,
                          border: "1px solid #fecaca",
                          background: "#fff5f5",
                          color: "#ef4444",
                          fontSize: 12,
                          cursor: "pointer",
                        }}
                      >
                        移除
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </main>
    </>
  );
}
