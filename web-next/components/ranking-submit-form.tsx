"use client";

import { ChangeEvent, FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import { SiteHeader } from "./site-header";
import { useSession } from "./session-provider";
import { formatError } from "../lib/format";
import { submitRankingToy, uploadImage } from "../lib/api/forum";

const categoryOptions = [
  ["cup", "飞机杯"],
  ["small_hip", "小型臀模"],
  ["large_hip", "大型臀模"],
  ["half_body", "半身腿模"],
  ["lubricant", "润滑油"],
] as const;

const intensityOptions = [
  ["beginner", "慢玩入门"],
  ["advanced", "进阶训练"],
  ["high_stim", "超高刺激"],
  ["juice", "榨汁玩具"],
] as const;

export function RankingSubmitForm() {
  const router = useRouter();
  const { user, ready } = useSession();
  const [name, setName] = useState("");
  const [merchant, setMerchant] = useState("");
  const [year, setYear] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("");
  const [intensity, setIntensity] = useState("");
  const [tagInput, setTagInput] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  const [cover, setCover] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  const coverPreview = useMemo(() => cover ? URL.createObjectURL(cover) : "", [cover]);
  useEffect(() => () => { if (coverPreview) URL.revokeObjectURL(coverPreview); }, [coverPreview]);

  function addTag() {
    const tag = tagInput.trim();
    if (!tag || tags.length >= 3 || tag.length > 4 || tags.includes(tag)) return;
    setTags((current) => [...current, tag]);
    setTagInput("");
  }

  function chooseCover(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (file?.type.startsWith("image/")) setCover(file);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) {
      router.push(`/login?next=${encodeURIComponent("/ranking/submit")}`);
      return;
    }
    if (user.accountType === "guest") {
      setError("游客账号不能投稿，请先完成正式账号登录");
      return;
    }
    const trimmedName = name.trim();
    if (!trimmedName) { setError("请填写玩具名称"); return; }
    if (!category) { setError("请选择品类"); return; }
    const yearValue = year.trim() ? Number(year.trim()) : undefined;
    if (yearValue !== undefined && (!Number.isInteger(yearValue) || yearValue < 1970 || yearValue > 2100)) {
      setError("年份必须在 1970 到 2100 之间");
      return;
    }
    const pendingTag = tagInput.trim();
    const submittedTags =
      pendingTag && tags.length < 3 && pendingTag.length <= 4 && !tags.includes(pendingTag)
        ? [...tags, pendingTag]
        : tags;

    if (pendingTag && !submittedTags.includes(pendingTag)) {
      setError("标签最多 4 个字，且不能重复；请先修正后再提交");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const coverMediaId = cover ? await uploadImage(cover) : undefined;
      await submitRankingToy({
        name: trimmedName,
        category,
        merchant: merchant.trim() || undefined,
        releaseYear: yearValue,
        description: description.trim() || undefined,
        coverMediaId,
        intensity: intensity || undefined,
        tags: submittedTags,
      });
      setSuccess(true);
    } catch (requestError) {
      setError(formatError(requestError, "投稿提交失败，请稍后重试"));
    } finally {
      setBusy(false);
    }
  }

  if (!ready) return <><SiteHeader /><main className="page-frame"><div className="detail-skeleton"><div /><div /></div></main></>;
  if (!user) return <><SiteHeader /><main className="page-frame"><section className="coming-page"><span className="coming-icon"><Icon name="trophy" size={26} /></span><h1>登录后才能投稿</h1><p>登录邮箱账号后，就可以把好物推荐给大家。</p><button type="button" className="primary-link" onClick={() => router.push(`/login?next=${encodeURIComponent("/ranking/submit")}`)}>去登录</button></section></main></>;

  return <>
    <SiteHeader />
    <main className="page-frame ranking-submit-frame">
      <section className="ranking-submit-page">
        <div className="ranking-submit-heading"><button type="button" className="back-link" onClick={() => router.push("/ranking")}><Icon name="chevron-left" size={17} />返回榜单</button><h1>投稿新玩具</h1><p>补充一件榜单里还没有的好物，提交后等待管理员审核。</p></div>
        {success ? <div className="ranking-submit-success" role="status"><span><Icon name="trophy" size={24} /></span><h2>已提交，等待管理员审核</h2><p>审核通过后，这件玩具会出现在榜单里。</p><button type="button" className="primary-submit" onClick={() => router.push("/ranking")}>返回榜单</button></div> : <form className="ranking-submit-form" onSubmit={(event) => void submit(event)}>
          <fieldset disabled={busy}><legend>基本信息</legend><label htmlFor="ranking-submit-name">玩具名称 <b>*</b></label><input id="ranking-submit-name" value={name} onChange={(event) => setName(event.target.value)} placeholder="填写玩具的完整名称" maxLength={50} required /><div className="ranking-submit-two-fields"><div><label htmlFor="ranking-submit-merchant">品牌</label><input id="ranking-submit-merchant" value={merchant} onChange={(event) => setMerchant(event.target.value)} placeholder="品牌（选填）" maxLength={60} /></div><div><label htmlFor="ranking-submit-year">年份</label><input id="ranking-submit-year" value={year} onChange={(event) => setYear(event.target.value.replace(/[^0-9]/g, ""))} placeholder="年份" inputMode="numeric" maxLength={4} /></div></div></fieldset>
          <fieldset disabled={busy}><legend>分类</legend><label>品类 <b>*</b></label><div className="ranking-submit-options">{categoryOptions.map(([value, label]) => <button key={value} type="button" className={category === value ? "selected" : ""} onClick={() => setCategory(category === value ? "" : value)}>{label}</button>)}</div><label>刺激度类型</label><div className="ranking-submit-options">{intensityOptions.map(([value, label]) => <button key={value} type="button" className={intensity === value ? "selected" : ""} onClick={() => setIntensity(intensity === value ? "" : value)}>{label}</button>)}</div></fieldset>
          <fieldset disabled={busy}><legend>内容补充</legend><label htmlFor="ranking-submit-tags">标签 <small>最多 3 个，每个 4 字</small></label><div className="ranking-submit-tag-input"><input id="ranking-submit-tags" value={tagInput} onChange={(event) => setTagInput(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") { event.preventDefault(); addTag(); } }} placeholder={tags.length < 3 ? "输入标签" : "已达到 3 个上限"} maxLength={4} disabled={tags.length >= 3} /><button type="button" onClick={addTag} disabled={tags.length >= 3}>添加</button></div>{tags.length > 0 && <div className="ranking-submit-tag-list">{tags.map((tag) => <span key={tag}>{tag}<button type="button" aria-label={`删除标签 ${tag}`} onClick={() => setTags((current) => current.filter((item) => item !== tag))}>×</button></span>)}</div>}<label htmlFor="ranking-submit-description">介绍</label><textarea id="ranking-submit-description" value={description} onChange={(event) => setDescription(event.target.value)} placeholder="简单介绍玩法与特点（选填）" rows={5} maxLength={2000} /><label htmlFor="ranking-submit-cover">封面图 <small>选填</small></label><div className="ranking-submit-cover-picker">{coverPreview ? <div className="ranking-submit-cover-preview"><img src={coverPreview} alt="封面预览" /><button type="button" aria-label="移除封面" onClick={() => setCover(null)}>×</button></div> : <label className="ranking-submit-cover-add"><Icon name="image" size={21} /><span>选择图片</span><input id="ranking-submit-cover" type="file" accept="image/*" onChange={chooseCover} /></label>}</div></fieldset>
          {error && <div className="form-error" role="alert">{error}</div>}<button type="submit" className="primary-submit ranking-submit-button">{busy ? (cover ? "上传并提交中…" : "提交中…") : "提交投稿"}</button>
        </form>}
      </section>
    </main>
  </>;
}
