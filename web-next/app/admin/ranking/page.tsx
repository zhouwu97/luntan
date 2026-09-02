"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { Icon } from "../../../components/icons";
import { SiteHeader } from "../../../components/site-header";
import { useSession } from "../../../components/session-provider";
import { ApiError } from "../../../lib/api/client";
import { getRankingAdminView, saveRankingAdminViewOrder } from "../../../lib/api/forum";
import { formatError } from "../../../lib/format";
import type { RankingAdminView, RankingAdminViewItem } from "../../../types/forum";

const adminTabs = [
  { label: "综合榜", key: "" },
  { label: "慢玩入门", key: "ENTRY" },
  { label: "进阶训练", key: "ADVANCED" },
  { label: "超高刺激", key: "HIGH" },
  { label: "榨汁玩具", key: "EXTREME" },
];

const adminCategories = [
  { label: "全部", key: "" },
  { label: "飞机杯", key: "CUP" },
  { label: "小型臀模", key: "SMALL_MOLD" },
  { label: "大型臀模", key: "LARGE_MOLD" },
  { label: "半身腿模", key: "HALF_BODY" },
  { label: "润滑油", key: "LUBE" },
];

function formatDay(value?: string): string {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "—"
    : new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).format(date);
}

export default function AdminRankingPage() {
  const { user, ready } = useSession();
  const isSuperAdmin = user?.capabilities?.can_manage_admins === true;
  const [tab, setTab] = useState("");
  const [category, setCategory] = useState("");
  const [items, setItems] = useState<RankingAdminViewItem[]>([]);
  const [weeklyTop, setWeeklyTop] = useState<RankingAdminView["weeklyTop"]>();
  const [mode, setMode] = useState<"AUTO" | "MANUAL">("AUTO");
  const [version, setVersion] = useState(0);
  const [syncedAt, setSyncedAt] = useState<string>();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const dragIndex = useRef<number | null>(null);

  useEffect(() => {
    if (!isSuperAdmin) return;
    let active = true;
    setLoading(true);
    setError("");
    setNotice("");
    setDirty(false);
    void getRankingAdminView(tab, category)
      .then((view) => {
        if (!active) return;
        setItems(view.items);
        setMode(view.sortMode);
        setVersion(view.version);
        setSyncedAt(view.syncedAt);
        setWeeklyTop(view.weeklyTop);
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "榜单视图暂时无法加载"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [category, isSuperAdmin, tab]);

  const confirmDiscardDirty = (): boolean => {
    if (!dirty) return true;
    return window.confirm("当前有未保存的排序调整，切换后将丢失。确定继续吗？");
  };

  const chooseTab = (key: string) => {
    if (key === tab) return;
    if (!confirmDiscardDirty()) return;
    // 综合榜没有品类维度；细分榜必须绑定品类，未选过时补默认品类。
    setTab(key);
    setCategory(key === "" ? "" : category === "" ? "CUP" : category);
  };

  const chooseCategory = (key: string) => {
    const next = key === "" && tab !== "" ? "CUP" : key;
    if (next === category) return;
    if (!confirmDiscardDirty()) return;
    setCategory(next);
  };

  const switchMode = (nextMode: "AUTO" | "MANUAL") => {
    if (nextMode === mode || saving) return;
    if (nextMode === "AUTO") {
      // 恢复自动必须真实落库：确认后直接 PUT mode=AUTO，成功后才切换 UI。
      if (!window.confirm("确认恢复自动排序？将清除当前视图的人工排序。")) return;
      void persist("AUTO", []);
      return;
    }
    // 切到 MANUAL 时以当前展示顺序（AUTO 顺序）作为人工排序初值，确认后再保存。
    setMode("MANUAL");
    setDirty(true);
    setNotice("");
    setError("");
  };

  const moveItem = useCallback((from: number, to: number) => {
    if (to < 0 || to === from) return;
    setItems((current) => {
      const next = [...current];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved);
      return next;
    });
    setDirty(true);
    setNotice("");
  }, []);

  const onDrop = (targetIndex: number) => {
    const from = dragIndex.current;
    dragIndex.current = null;
    if (from === null || from === targetIndex) return;
    moveItem(from, targetIndex);
  };

  async function persist(nextMode: "AUTO" | "MANUAL", orderedToyIds: string[]) {
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const result = await saveRankingAdminViewOrder({ tab, category, mode: nextMode, orderedToyIds, version });
      setVersion(result.version);
      setMode(result.mode);
      setDirty(false);
      const refreshed = await getRankingAdminView(tab, category);
      setItems(refreshed.items);
      setVersion(refreshed.version);
      setMode(refreshed.sortMode);
      setSyncedAt(refreshed.syncedAt);
      setWeeklyTop(refreshed.weeklyTop);
      setNotice(nextMode === "MANUAL" ? "排序已保存" : "已恢复自动排序");
    } catch (requestError: unknown) {
      if (requestError instanceof ApiError && (requestError.status === 409 || requestError.code === "RANKING_VIEW_ORDER_STALE")) {
        // 乐观锁冲突与“商品不属于当前视图”共用 409，透出服务端的具体原因。
        setError(requestError.message || "榜单已被其他管理员修改，请刷新后重试");
        try {
          const refreshed = await getRankingAdminView(tab, category);
          setItems(refreshed.items);
          setVersion(refreshed.version);
          setMode(refreshed.sortMode);
          setSyncedAt(refreshed.syncedAt);
          setWeeklyTop(refreshed.weeklyTop);
          setDirty(false);
        } catch {
          // 刷新失败时保留错误提示
        }
      } else {
        setError(formatError(requestError, "保存排序失败，请稍后再试"));
      }
    } finally {
      setSaving(false);
    }
  }

  if (!ready) {
    return <main className="page-frame admin-ranking-page"><div className="admin-ranking-gate" role="status">正在确认身份…</div></main>;
  }
  if (!isSuperAdmin) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame admin-ranking-page">
          <div className="admin-ranking-gate">
            <h1>暂无访问权限</h1>
            <p>榜单排序管理仅对超级管理员开放。</p>
            {user ? <Link className="admin-ranking-gate-link" href="/">返回首页</Link> : <Link className="admin-ranking-gate-link" href="/login">去登录</Link>}
          </div>
        </main>
      </>
    );
  }

  return (
    <>
      <SiteHeader />
      <main className="page-frame admin-ranking-page">
        <header className="admin-ranking-head">
          <h1>榜单排序管理</h1>
          <p>原始榜单名次始终保留，这里只调整展示顺序；重新同步不会覆盖人工排序。</p>
          <div className="admin-ranking-meta">
            <span>原始榜单已同步：{formatDay(syncedAt)}</span>
            <span>当前模式：{mode === "MANUAL" ? "人工排序" : "自动（按源榜单）"}</span>
          </div>
        </header>

        <div className="admin-ranking-filters">
          <div className="admin-ranking-filter" role="tablist" aria-label="榜单视图">
            {adminTabs.map((item) => (
              <button key={item.key} type="button" className={tab === item.key ? "active" : ""} onClick={() => chooseTab(item.key)}>{item.label}</button>
            ))}
          </div>
          {tab !== "" && (
            <div className="admin-ranking-filter" role="tablist" aria-label="品类">
              {adminCategories.map((item) => (
                <button key={item.key} type="button" className={category === item.key ? "active" : ""} onClick={() => chooseCategory(item.key)}>{item.label}</button>
              ))}
            </div>
          )}
          <div className="admin-ranking-modes">
            <button type="button" className={mode === "AUTO" ? "active" : ""} disabled={saving} onClick={() => switchMode("AUTO")}>自动排序</button>
            <button type="button" className={mode === "MANUAL" ? "active" : ""} disabled={saving} onClick={() => switchMode("MANUAL")}>人工排序</button>
          </div>
        </div>

        {error && <div className="admin-ranking-message error" role="alert">{error}</div>}
        {notice && <div className="admin-ranking-message" role="status">{notice}</div>}

        {loading ? (
          <div className="admin-ranking-state" role="status">正在加载榜单…</div>
        ) : items.length === 0 ? (
          <div className="admin-ranking-state" role="status">该视图暂无商品。</div>
        ) : (
          <>
            {weeklyTop && (
              <aside className="admin-ranking-weekly">
                <div className="admin-ranking-weekly-badge">本周推荐</div>
                {weeklyTop.coverUrl
                  ? <img className="admin-ranking-cover" src={weeklyTop.coverUrl} alt="" loading="lazy" />
                  : <span className="admin-ranking-cover placeholder" aria-hidden="true"><Icon name="box" size={18} /></span>}
                <div className="admin-ranking-weekly-info">
                  <strong>{weeklyTop.name}</strong>
                  <span>源名次 {weeklyTop.sourceRank || "—"}</span>
                </div>
                <p className="admin-ranking-weekly-note">首页置顶大卡随源站数据同步产生，与这里的拖拽排序无关；把商品拖到第一位不会改变首页推荐。</p>
              </aside>
            )}
            <ol className="admin-ranking-list">
              {items.map((item, index) => (
                <li
                  key={item.toyId}
                  className={`admin-ranking-row${mode === "MANUAL" ? " draggable" : ""}`}
                  draggable={mode === "MANUAL"}
                  onDragStart={() => { dragIndex.current = index; }}
                  onDragOver={(event) => { if (mode === "MANUAL") event.preventDefault(); }}
                  onDrop={() => onDrop(index)}
                >
                  <span className="admin-ranking-order">{index + 1}</span>
                  <span className="admin-ranking-grip" aria-hidden="true">☰</span>
                  {item.coverUrl
                    ? <img className="admin-ranking-cover" src={item.coverUrl} alt="" loading="lazy" />
                    : <span className="admin-ranking-cover placeholder" aria-hidden="true"><Icon name="box" size={18} /></span>}
                  <span className="admin-ranking-name">
                    {item.name}
                    {item.manualPosition == null && mode === "MANUAL" && <em className="admin-ranking-new">NEW 待排序</em>}
                  </span>
                  <span className="admin-ranking-source">源名次 {item.sourceRank || "—"}</span>
                  <span className="admin-ranking-move">
                    <button type="button" aria-label={`把${item.name}上移`} disabled={mode !== "MANUAL" || index === 0 || saving} onClick={() => moveItem(index, index - 1)}>↑</button>
                    <button type="button" aria-label={`把${item.name}下移`} disabled={mode !== "MANUAL" || index === items.length - 1 || saving} onClick={() => moveItem(index, index + 1)}>↓</button>
                  </span>
                </li>
              ))}
            </ol>
            <div className="admin-ranking-actions">
              <button
                type="button"
                className="admin-ranking-save"
                disabled={saving || loading || mode !== "MANUAL"}
                onClick={() => void persist("MANUAL", items.map((item) => item.toyId))}
              >
                {saving ? "正在保存…" : "保存排序"}
              </button>
              {mode === "MANUAL" && <span className="admin-ranking-hint">调整为人工排序后需点击保存才会生效。</span>}
            </div>
          </>
        )}
      </main>
    </>
  );
}
