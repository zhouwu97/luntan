"use client";

import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "./site-header";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { useToast } from "./toast-context";
import {
  cleanupUploadedMedia,
  createPost,
  getCommunities,
  isDeterministicClientError,
  isPossiblySupportedImageFile,
  uploadImages,
  webImageAccept,
} from "../lib/api/forum";
import { formatError } from "../lib/format";
import type { Community } from "../types/forum";

const MAX_IMAGES = 9;
const DRAFT_KEY_PREFIX = "shengbeijiang_post_draft";
type PublishPostType = "normal" | "poll" | "game_share";

export function PublishForm() {
  const router = useRouter();
  const { user, ready } = useSession();
  const { showToast } = useToast();
  const [communities, setCommunities] = useState<Community[]>([]);
  const [communityId, setCommunityId] = useState("");
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [postType, setPostType] = useState<PublishPostType>("normal");
  const [pollQuestion, setPollQuestion] = useState("");
  const [pollOptions, setPollOptions] = useState<string[]>(["", ""]);
  const [allowMultiple, setAllowMultiple] = useState(false);
  const [pollEndsAt, setPollEndsAt] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [loadingCommunities, setLoadingCommunities] = useState(true);
  const [error, setError] = useState("");
  const [hasDraftRestored, setHasDraftRestored] = useState(false);
  const restoringDraftRef = useRef(false);
  const restoredDraftKeyRef = useRef<string | null>(null);
  const autoSaveDraftKeyRef = useRef<string | null>(null);
  const draftKey = ready && user?.id ? `${DRAFT_KEY_PREFIX}:${user.id}` : null;

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
    if (!ready || !draftKey) {
      restoringDraftRef.current = false;
      restoredDraftKeyRef.current = null;
      autoSaveDraftKeyRef.current = null;
      return;
    }

    restoringDraftRef.current = true;
    restoredDraftKeyRef.current = null;
    autoSaveDraftKeyRef.current = null;
    setTitle("");
    setContent("");
    setCommunityId("");
    setFiles([]);
    setPostType("normal");
    setPollQuestion("");
    setPollOptions(["", ""]);
    setAllowMultiple(false);
    setPollEndsAt("");
    setHasDraftRestored(false);
    try {
      const saved = localStorage.getItem(draftKey);
      if (saved) {
        const data = JSON.parse(saved);
        if (data.title || data.content) {
          setTitle(data.title || "");
          setContent(data.content || "");
          if (data.communityId) setCommunityId(data.communityId);
          if (data.postType === "poll" || data.postType === "game_share") setPostType(data.postType);
          if (typeof data.pollQuestion === "string") setPollQuestion(data.pollQuestion);
          if (Array.isArray(data.pollOptions) && data.pollOptions.length >= 2) setPollOptions(data.pollOptions.map(String).slice(0, 10));
          if (typeof data.allowMultiple === "boolean") setAllowMultiple(data.allowMultiple);
          if (typeof data.pollEndsAt === "string") setPollEndsAt(data.pollEndsAt);
          setHasDraftRestored(true);
        }
      }
    } catch {
      // Ignore storage read error
    } finally {
      restoredDraftKeyRef.current = draftKey;
      restoringDraftRef.current = false;
    }
  }, [draftKey, ready]);

  // 自动保存草稿
  useEffect(() => {
    if (busy || !ready || !draftKey || restoringDraftRef.current || restoredDraftKeyRef.current !== draftKey) return;
    // 账号切换后的第一次 effect 只建立新账号的保存上下文，避免把旧账号的 React 状态写入新 key。
    if (autoSaveDraftKeyRef.current !== draftKey) {
      autoSaveDraftKeyRef.current = draftKey;
      return;
    }
    try {
      if (title.trim() || content.trim() || postType !== "normal") {
        localStorage.setItem(
          draftKey,
          JSON.stringify({ title, content, communityId, postType, pollQuestion, pollOptions, allowMultiple, pollEndsAt, updatedAt: Date.now() }),
        );
      } else {
        localStorage.removeItem(draftKey);
      }
    } catch {
      // Ignore storage write error
    }
  }, [allowMultiple, busy, communityId, content, draftKey, pollEndsAt, pollOptions, pollQuestion, postType, ready, title]);

  // 页面离开防丢保护
  useEffect(() => {
    const handleBeforeUnload = (event: BeforeUnloadEvent) => {
      if ((title.trim() || content.trim() || files.length > 0 || postType !== "normal") && !busy) {
        event.preventDefault();
        event.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, [busy, content, files.length, postType, title]);

  useEffect(() => {
    if (!ready) return;
    if (!user || user.accountType === "guest") {
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
    setPostType("normal");
    setPollQuestion("");
    setPollOptions(["", ""]);
    setAllowMultiple(false);
    setPollEndsAt("");
    setHasDraftRestored(false);
    try {
      if (draftKey) localStorage.removeItem(draftKey);
    } catch {
      // Ignore
    }
    showToast("草稿已清空");
  }

  function chooseImages(event: ChangeEvent<HTMLInputElement>) {
    const next = Array.from(event.target.files || []);
    event.target.value = "";
    if (!next.length) return;
    const images = next.filter(isPossiblySupportedImageFile);
    if (images.length !== next.length) setError("仅支持 JPG、PNG、GIF、WebP 图片");
    setFiles((current) => [...current, ...images].slice(0, MAX_IMAGES));
  }

  function updatePollOption(index: number, value: string) {
    setPollOptions((current) => current.map((option, optionIndex) => optionIndex === index ? value : option));
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
    if (postType === "poll") {
      if (!selectedCommunity?.canCreatePoll || user.capabilities?.can_create_poll === false) {
        setError("当前账号或板块暂不允许创建投票");
        return;
      }
      const options = pollOptions.map((option) => option.trim()).filter(Boolean);
      const unique = new Set(options);
      if (!pollQuestion.trim()) {
        setError("请填写投票问题");
        return;
      }
      if (options.length < 2 || options.length > 10 || unique.size !== options.length) {
        setError("投票需要 2 到 10 个不重复选项");
        return;
      }
      if ([...pollQuestion].length > 200 || options.some((option) => [...option].length > 200)) {
        setError("投票问题和选项不能超过 200 个字符");
        return;
      }
    }
    if (files.length && !selectedCommunity.canUploadMedia) {
      setError("当前账号或板块暂不允许上传图片");
      return;
    }

    setBusy(true);
    setError("");
    let mediaIds: string[] = [];
    try {
      mediaIds = files.length ? await uploadImages(files) : [];
      const post = await createPost(communityId, title.trim(), content.trim(), mediaIds, {
        type: postType,
        ...(postType === "poll"
          ? {
              poll: {
                question: pollQuestion.trim(),
                options: pollOptions.map((option) => option.trim()).filter(Boolean),
                allowMultiple,
                ...(pollEndsAt ? { endsAt: new Date(pollEndsAt).toISOString() } : {}),
              },
            }
          : {}),
      });
      try {
        if (draftKey) localStorage.removeItem(draftKey);
      } catch {
        // Ignore
      }
      showToast("帖子发布成功！");
      router.replace(`/post/${encodeURIComponent(post.id)}`);
    } catch (requestError) {
      // 仅在服务端明确拒绝时回收；网络超时可能对应服务端已成功创建，不能误删已关联媒体。
      if (mediaIds.length > 0 && isDeterministicClientError(requestError)) {
        await cleanupUploadedMedia(mediaIds);
      }
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

  if (user.accountType === "guest") {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <section className="coming-page">
            <span className="coming-icon"><Icon name="user" size={26} /></span>
            <h1>注册后才能发布内容</h1>
            <p>注册正式账号后即可发布帖子，当前游客浏览、评论与经验会继续保留。</p>
            <button
              type="button"
              className="primary-link"
              onClick={() => router.push(`/login?mode=register&next=${encodeURIComponent("/publish")}`)}
            >
              注册正式账号
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

            <label className="field-label" htmlFor="publish-type">
              帖子类型
            </label>
            <select
              id="publish-type"
              className="text-input"
              value={postType}
              onChange={(event) => setPostType(event.target.value as PublishPostType)}
              disabled={busy}
            >
              <option value="normal">普通帖子</option>
              <option
                value="poll"
                disabled={!selectedCommunity?.canCreatePoll || user.capabilities?.can_create_poll === false}
              >
                投票
              </option>
              <option value="game_share">玩法分享</option>
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

            {postType === "poll" && (
              <section
                aria-label="投票编辑器"
                style={{ display: "grid", gap: 9, padding: 14, border: "1px solid #dbeafe", borderRadius: 12, background: "#f8fbff" }}
              >
                <strong style={{ fontSize: 14 }}>投票设置</strong>
                <label className="field-label" htmlFor="poll-question">投票问题</label>
                <input
                  id="poll-question"
                  className="text-input"
                  value={pollQuestion}
                  onChange={(event) => setPollQuestion(event.target.value)}
                  maxLength={200}
                  placeholder="例如：下次想看哪类测评？"
                  disabled={busy}
                />
                <span className="field-label">投票选项（2–10 项）</span>
                {pollOptions.map((option, index) => (
                  <div key={index} style={{ display: "flex", gap: 8 }}>
                    <input
                      className="text-input"
                      aria-label={`投票选项 ${index + 1}`}
                      value={option}
                      onChange={(event) => updatePollOption(index, event.target.value)}
                      maxLength={200}
                      placeholder={`选项 ${index + 1}`}
                      disabled={busy}
                    />
                    {pollOptions.length > 2 && (
                      <button
                        type="button"
                        className="outline-button"
                        aria-label={`删除投票选项 ${index + 1}`}
                        onClick={() => setPollOptions((current) => current.filter((_, optionIndex) => optionIndex !== index))}
                        disabled={busy}
                      >
                        删除
                      </button>
                    )}
                  </div>
                ))}
                {pollOptions.length < 10 && (
                  <button type="button" className="outline-button" onClick={() => setPollOptions((current) => [...current, ""])} disabled={busy}>
                    添加选项
                  </button>
                )}
                <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13, color: "#475569" }}>
                  <input type="checkbox" checked={allowMultiple} onChange={(event) => setAllowMultiple(event.target.checked)} disabled={busy} />
                  允许多选
                </label>
                <label className="field-label" htmlFor="poll-ends-at">截止时间（可选）</label>
                <input id="poll-ends-at" className="text-input" type="datetime-local" value={pollEndsAt} onChange={(event) => setPollEndsAt(event.target.value)} disabled={busy} />
              </section>
            )}

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
                  accept={webImageAccept}
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
                {busy ? (files.length ? "上传并发布中…" : "发布中…") : postType === "poll" ? "发布投票" : "发布帖子"}
              </button>
            </div>
          </form>
        </section>
      </main>
    </>
  );
}
