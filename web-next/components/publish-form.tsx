"use client";

import { ChangeEvent, FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "./site-header";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { useToast } from "./toast-context";
import { createPost, getCommunities, uploadImage } from "../lib/api/forum";
import { formatError } from "../lib/format";
import type { Community } from "../types/forum";

const MAX_IMAGES = 9;
const DRAFT_KEY = "shengbeijiang_post_draft";

export function PublishForm() {
  const router = useRouter();
  const { user, ready } = useSession();
  const { showToast } = useToast();
  const [communities, setCommunities] = useState<Community[]>([]);
  const [communityId, setCommunityId] = useState("");
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [loadingCommunities, setLoadingCommunities] = useState(true);
  const [error, setError] = useState("");
  const [hasDraftRestored, setHasDraftRestored] = useState(false);

  const selectedCommunity = useMemo(
    () => communities.find((community) => community.id === communityId),
    [communities, communityId],
  );

  const previews = useMemo(
    () => files.map((file) => ({ file, url: URL.createObjectURL(file) })),
    [files],
  );

  useEffect(() => () => previews.forEach((item) => URL.revokeObjectURL(item.url)), [previews]);

  // 加载草稿
  useEffect(() => {
    try {
      const saved = localStorage.getItem(DRAFT_KEY);
      if (saved) {
        const data = JSON.parse(saved);
        if (data.title || data.content) {
          setTitle(data.title || "");
          setContent(data.content || "");
          if (data.communityId) setCommunityId(data.communityId);
          setHasDraftRestored(true);
        }
      }
    } catch {
      // Ignore storage read error
    }
  }, []);

  // 自动保存草稿
  useEffect(() => {
    if (busy) return;
    try {
      if (title.trim() || content.trim()) {
        localStorage.setItem(
          DRAFT_KEY,
          JSON.stringify({ title, content, communityId, updatedAt: Date.now() }),
        );
      }
    } catch {
      // Ignore storage write error
    }
  }, [busy, communityId, content, title]);

  // 页面离开防丢保护
  useEffect(() => {
    const handleBeforeUnload = (event: BeforeUnloadEvent) => {
      if ((title.trim() || content.trim() || files.length > 0) && !busy) {
        event.preventDefault();
        event.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, [busy, content, files.length, title]);

  useEffect(() => {
    if (!ready) return;
    if (!user) {
      setLoadingCommunities(false);
      return;
    }
    let active = true;
    setLoadingCommunities(true);
    void getCommunities({ canPublish: true, status: "active" })
      .then((items) => {
        if (!active) return;
        setCommunities(items);
        setCommunityId((current) =>
          current && items.some((item) => item.id === current) ? current : items[0]?.id || "",
        );
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "可发布板块加载失败"));
      })
      .finally(() => {
        if (active) setLoadingCommunities(false);
      });
    return () => {
      active = false;
    };
  }, [ready, user]);

  function clearDraft() {
    setTitle("");
    setContent("");
    setFiles([]);
    setHasDraftRestored(false);
    try {
      localStorage.removeItem(DRAFT_KEY);
    } catch {
      // Ignore
    }
    showToast("草稿已清空");
  }

  function chooseImages(event: ChangeEvent<HTMLInputElement>) {
    const next = Array.from(event.target.files || []);
    event.target.value = "";
    if (!next.length) return;
    const images = next.filter((file) => file.type.startsWith("image/"));
    setFiles((current) => [...current, ...images].slice(0, MAX_IMAGES));
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) {
      router.push("/login");
      return;
    }
    if (user.accountType === "guest") {
      setError("游客账号不能发布帖子，请先完成正式账号登录");
      return;
    }
    if (!communityId || !selectedCommunity?.canPublish) {
      setError("当前账号没有可发布的板块");
      return;
    }
    if (!title.trim() || !content.trim()) {
      setError("请先填写标题和正文");
      return;
    }
    if (files.length && !selectedCommunity.canUploadMedia) {
      setError("当前账号或板块暂不允许上传图片");
      return;
    }

    setBusy(true);
    setError("");
    try {
      const mediaIds: string[] = [];
      for (const file of files) mediaIds.push(await uploadImage(file));
      const post = await createPost(communityId, title.trim(), content.trim(), mediaIds);
      try {
        localStorage.removeItem(DRAFT_KEY);
      } catch {
        // Ignore
      }
      showToast("帖子发布成功！");
      router.replace(`/post/${encodeURIComponent(post.id)}`);
    } catch (requestError) {
      setError(formatError(requestError, "发布失败，请稍后再试"));
    } finally {
      setBusy(false);
    }
  }

  if (!ready) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <div className="detail-skeleton">
            <div />
            <div />
          </div>
        </main>
      </>
    );
  }

  if (!user) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <section className="coming-page">
            <span className="coming-icon">
              <Icon name="user" size={26} />
            </span>
            <h1>登录后才能发布内容</h1>
            <p>先登录邮箱账号，再和社区分享你的新发现。</p>
            <button
              type="button"
              className="primary-link"
              onClick={() => router.push("/login")}
            >
              去登录
            </button>
          </section>
        </main>
      </>
    );
  }

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="publish-page">
          <div className="publish-heading">
            <button type="button" className="back-link" onClick={() => router.back()}>
              <Icon name="chevron-left" size={17} />
              返回
            </button>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
              <h1>发布帖子</h1>
              {hasDraftRestored && (
                <div style={{ display: "flex", alignItems: "center", gap: 10, fontSize: 12, color: "#059669" }}>
                  <span>已自动恢复上次草稿</span>
                  <button
                    type="button"
                    onClick={clearDraft}
                    style={{ background: "none", border: 0, color: "#ef4444", cursor: "pointer", textDecoration: "underline", fontSize: 12 }}
                  >
                    放弃草稿
                  </button>
                </div>
              )}
            </div>
          </div>

          <form className="publish-form" onSubmit={submit}>
            <label className="field-label" htmlFor="publish-community">
              发布到
            </label>
            <select
              id="publish-community"
              className="text-input"
              value={communityId}
              onChange={(event) => setCommunityId(event.target.value)}
              disabled={loadingCommunities || busy}
            >
              {!communities.length && (
                <option value="">
                  {loadingCommunities ? "正在加载可发布板块…" : "暂无可发布板块"}
                </option>
              )}
              {communities.map((community) => (
                <option key={community.id} value={community.id}>
                  {community.name}
                </option>
              ))}
            </select>

            <label className="field-label" htmlFor="publish-title">
              标题
            </label>
            <input
              id="publish-title"
              className="text-input"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="给这次分享起个标题"
              maxLength={120}
              disabled={busy}
            />

            <label className="field-label" htmlFor="publish-content">
              正文
            </label>
            <textarea
              id="publish-content"
              className="publish-textarea"
              value={content}
              onChange={(event) => setContent(event.target.value)}
              placeholder="说说你的真实体验、问题或发现…"
              rows={11}
              maxLength={10000}
              disabled={busy}
            />

            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: 12,
                flexWrap: "wrap",
              }}
            >
              <label
                className="outline-button"
                style={{
                  cursor: busy || !selectedCommunity?.canUploadMedia ? "not-allowed" : "pointer",
                }}
              >
                <Icon name="image" size={17} /> 添加图片（{files.length}/{MAX_IMAGES}）
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  hidden
                  onChange={chooseImages}
                  disabled={busy || !selectedCommunity?.canUploadMedia || files.length >= MAX_IMAGES}
                />
              </label>
              {selectedCommunity && !selectedCommunity.canUploadMedia && (
                <span style={{ fontSize: 13, opacity: 0.7 }}>当前板块/账号无图片上传权限</span>
              )}
            </div>

            {previews.length > 0 && (
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(auto-fill,minmax(110px,1fr))",
                  gap: 10,
                }}
              >
                {previews.map(({ file, url }, index) => (
                  <div
                    key={`${file.name}-${file.lastModified}-${index}`}
                    style={{
                      position: "relative",
                      aspectRatio: "1",
                      overflow: "hidden",
                      borderRadius: 10,
                      border: "1px solid var(--line, #e5e7eb)",
                    }}
                  >
                    <img
                      src={url}
                      alt="待上传图片预览"
                      style={{ width: "100%", height: "100%", objectFit: "cover" }}
                    />
                    <button
                      type="button"
                      aria-label="移除图片"
                      onClick={() =>
                        setFiles((current) => current.filter((_, fileIndex) => fileIndex !== index))
                      }
                      disabled={busy}
                      style={{
                        position: "absolute",
                        right: 6,
                        top: 6,
                        width: 28,
                        height: 28,
                        borderRadius: 14,
                        border: 0,
                        background: "rgba(0,0,0,.62)",
                        color: "white",
                        cursor: "pointer",
                      }}
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>
            )}

            {error && <div className="form-error">{error}</div>}
            <div className="publish-footer">
              <span>{content.length}/10000</span>
              <button
                type="submit"
                className="primary-submit publish-submit"
                disabled={busy || loadingCommunities || !communityId}
              >
                {busy ? (files.length ? "上传并发布中…" : "发布中…") : "发布帖子"}
              </button>
            </div>
          </form>
        </section>
      </main>
    </>
  );
}
