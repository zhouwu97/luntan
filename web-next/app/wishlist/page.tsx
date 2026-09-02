"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { Icon } from "../../components/icons";
import { MediaImage } from "../../components/media-image";
import { getRankingToy } from "../../lib/api/forum";
import { formatError } from "../../lib/format";
import { readRankingToyCache, writeRankingToyCache } from "../../lib/ranking-client-cache";
import type { RankingToy } from "../../types/forum";

export default function WishlistPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const id = searchParams.get("id") || "";
  const [item, setItem] = useState<RankingToy | null>(null);
  const [loading, setLoading] = useState(Boolean(id));
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    if (!id) return;
    let active = true;
    const cached = readRankingToyCache(id);
    setItem(cached);
    setLoading(!cached);
    setError("");
    void getRankingToy(id)
      .then((nextItem) => { if (active) { setItem(nextItem); writeRankingToyCache(nextItem); } })
      .catch((requestError: unknown) => { if (active) setError(formatError(requestError, "想冲清单暂时无法加载")); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [id]);

  async function openCoupon() {
    if (!item?.couponUrl) {
      setNotice("暂时没找到优惠券");
      return;
    }
    window.open(item.couponUrl, "_blank", "noopener,noreferrer");
  }

  async function copyCoupon() {
    if (!item?.couponUrl) return;
    await navigator.clipboard?.writeText(item.couponUrl);
    setNotice("优惠券链接已复制");
  }

  return (
    <>
      <SiteHeader className="wishlist-site-header" />
      <div className="wishlist-mobile-header"><button type="button" aria-label="返回商品详情" onClick={() => router.push(`/ranking/${encodeURIComponent(id)}`)}><Icon name="chevron-left" size={22} /></button><h1>想冲清单</h1></div>
      <main className="page-frame wishlist-page">
        <button type="button" className="back-link wishlist-desktop-back" onClick={() => router.push(`/ranking/${encodeURIComponent(id)}`)}><Icon name="chevron-left" size={17} />返回商品详情</button>
        {loading && <div className="detail-skeleton"><div /><div /></div>}
        {!loading && item && <section className="wishlist-card"><div className="wishlist-image"><MediaImage sources={[item.coverUrl, item.heroUrl]} alt={item.name} loading="eager" /></div><h2>{item.name}</h2><p>已加入想冲清单，可直接领取或查看优惠。</p>{item.couponUrl ? <a className="wishlist-coupon-url" href={item.couponUrl} target="_blank" rel="noreferrer">{item.couponUrl}</a> : <span className="wishlist-no-coupon">暂时没找到优惠券</span>}<button type="button" className="wishlist-open-button" onClick={() => void openCoupon()}><Icon name="tag" size={17} />打开优惠券链接</button><button type="button" className="wishlist-copy-button" disabled={!item.couponUrl} onClick={() => void copyCoupon()}><Icon name="copy" size={17} />复制链接</button>{notice && <div className="form-message" role="status">{notice}</div>}</section>}
        {!loading && !item && <div className="empty-state"><h1>想冲清单为空</h1><p>{error || "从榜单商品详情加入一件喜欢的商品吧。"}</p><button type="button" className="primary-link" onClick={() => router.push("/ranking")}>浏览榜单</button></div>}
      </main>
    </>
  );
}
