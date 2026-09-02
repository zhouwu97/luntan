"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "./site-header";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { createPost, getCommunities } from "../lib/api/forum";
import { fallbackCommunities } from "../lib/fallback-data";
import { formatError } from "../lib/format";
import type { Community } from "../types/forum";

export function PublishForm() {
  const router = useRouter();
  const { user } = useSession();
  const [communities, setCommunities] = useState<Community[]>(fallbackCommunities);
  const [communityId, setCommunityId] = useState(fallbackCommunities[0].id);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!user) return;
    void getCommunities().then((items) => {
      if (!items.length) return;
      setCommunities(items);
      setCommunityId(items[0].id);
    }).catch(() => undefined);
  }, [user]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) {
      router.push("/login");
      return;
    }
    if (!title.trim() || !content.trim()) {
      setError("请先填写标题和正文");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const post = await createPost(communityId, title.trim(), content.trim());
      router.replace(`/post/${encodeURIComponent(post.id)}`);
    } catch (requestError) {
      setError(formatError(requestError, "发布失败，请稍后再试"));
    } finally {
      setBusy(false);
    }
  }

  if (!user) {
    return <><SiteHeader /><main className="page-frame"><section className="coming-page"><span className="coming-icon"><Icon name="user" size={26} /></span><h1>登录后才能发布内容</h1><p>先登录邮箱账号，再和社区分享你的新发现。</p><button type="button" className="primary-link" onClick={() => router.push("/login")}>去登录</button></section></main></>;
  }

  return <><SiteHeader /><main className="page-frame"><section className="publish-page"><div className="publish-heading"><button type="button" className="back-link" onClick={() => router.back()}><Icon name="chevron-left" size={17} />返回</button><h1>发布帖子</h1><span>分享真实体验，和同好聊聊</span></div><form className="publish-form" onSubmit={submit}><label className="field-label" htmlFor="publish-community">发布到</label><select id="publish-community" className="text-input" value={communityId} onChange={(event) => setCommunityId(event.target.value)}>{communities.map((community) => <option key={community.id} value={community.id}>{community.name}</option>)}</select><label className="field-label" htmlFor="publish-title">标题</label><input id="publish-title" className="text-input" value={title} onChange={(event) => setTitle(event.target.value)} placeholder="给这次分享起个标题" maxLength={120} /><label className="field-label" htmlFor="publish-content">正文</label><textarea id="publish-content" className="publish-textarea" value={content} onChange={(event) => setContent(event.target.value)} placeholder="说说你的真实体验、问题或发现…" rows={11} maxLength={10000} />{error && <div className="form-error">{error}</div>}<div className="publish-footer"><span>{content.length}/10000</span><button type="submit" className="primary-submit publish-submit" disabled={busy}>{busy ? "发布中…" : "发布帖子"}</button></div></form></section></main></>;
}
