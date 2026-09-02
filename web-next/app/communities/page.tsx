"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { SiteHeader } from "../../components/site-header";
import { Icon, type IconName } from "../../components/icons";
import { getCommunities } from "../../lib/api/forum";
import { formatError } from "../../lib/format";
import { normalizeCommunityDirectory } from "../../lib/home-communities";
import type { Community } from "../../types/forum";

const tones: Array<{ icon: IconName; tone: string }> = [
  { icon: "box", tone: "orange" },
  { icon: "trophy", tone: "lilac" },
  { icon: "sparkle", tone: "mint" },
  { icon: "flame", tone: "blue" },
];

export default function CommunitiesPage() {
  const [items, setItems] = useState<Community[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    void getCommunities({ status: "active" })
      .then((next) => { if (active) setItems(normalizeCommunityDirectory(next)); })
      .catch((requestError: unknown) => { if (active) setError(formatError(requestError, "社区暂时无法加载，请稍后再试")); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, []);

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page communities-page">
          <div className="feature-hero compact-hero"><div><span className="feature-kicker"><Icon name="box" size={16} /> 社区目录</span><h1>浏览全部社区</h1><p>首页只展示三个核心板块，其他公开社区都在这里。</p></div><Link href="/" className="outline-button feature-back">回到首页</Link></div>
          {error && <div className="data-note" role="status">{error}</div>}
          {loading ? <div className="community-directory-list"><div className="community-directory-skeleton" /><div className="community-directory-skeleton" /></div> : items.length ? <div className="community-directory-list">{items.map((community, index) => <CommunityDirectoryRow key={community.id} community={community} index={index} />)}</div> : <div className="empty-state feature-empty"><span className="empty-icon"><Icon name="box" size={24} /></span><h2>暂时没有公开社区</h2><p>稍后再来看看吧。</p></div>}
        </section>
      </main>
    </>
  );
}

function CommunityDirectoryRow({ community, index }: { community: Community; index: number }) {
  const style = tones[index % tones.length];
  return <Link href={`/community/${encodeURIComponent(community.id)}`} className="community-directory-row"><span className={`community-icon ${style.tone}`}><Icon name={style.icon} size={20} /></span><span className="community-directory-copy"><strong>{community.name}</strong><small>{community.description || "和同好聊聊最近的新发现"}</small></span><span className="community-directory-meta"><span>{community.postCount} 帖子</span><span>{community.followerCount} 关注</span></span><Icon name="chevron-right" size={18} /></Link>;
}
