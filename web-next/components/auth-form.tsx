"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { formatError } from "../lib/format";
import { requestEmailCode } from "../lib/api/forum";

export function AuthForm() {
  const router = useRouter();
  const { user, signInWithCode, signInAsGuest } = useSession();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [seconds, setSeconds] = useState(0);
  const [devCode, setDevCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [guestBusy, setGuestBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    if (seconds <= 0) return;
    const timer = window.setInterval(() => setSeconds((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [seconds]);

  useEffect(() => {
    if (user) router.replace("/");
  }, [router, user]);

  async function handleRequestCode() {
    const value = email.trim();
    if (!/^\S+@\S+\.\S+$/.test(value)) {
      setError("请输入有效的邮箱地址");
      return;
    }
    setBusy(true);
    setError("");
    setMessage("");
    try {
      const challenge = await requestEmailCode(value);
      setSeconds(challenge.retryAfter);
      setDevCode(challenge.devCode || "");
      setMessage(challenge.devCode ? "本地开发验证码已返回，请填写后登录" : "验证码已发送到你的邮箱，10 分钟内有效");
    } catch (requestError) {
      setError(formatError(requestError, "验证码发送失败，请稍后再试"));
    } finally {
      setBusy(false);
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email.trim() || !code.trim()) {
      setError("请填写邮箱和验证码");
      return;
    }
    setBusy(true);
    setError("");
    try {
      await signInWithCode(email.trim(), code.trim());
      router.replace("/");
    } catch (requestError) {
      setError(formatError(requestError, "验证码登录失败，请检查后重试"));
    } finally {
      setBusy(false);
    }
  }

  async function handleGuest() {
    setGuestBusy(true);
    setError("");
    try {
      await signInAsGuest();
      router.replace("/");
    } catch (requestError) {
      setError(formatError(requestError, "游客进入失败，请稍后重试"));
    } finally {
      setGuestBusy(false);
    }
  }

  return (
    <main className="auth-page">
      <div className="auth-glow auth-glow-one" />
      <div className="auth-glow auth-glow-two" />
      <section className="auth-card">
        <button type="button" className="back-link" onClick={() => router.push("/")}><Icon name="chevron-left" size={17} />返回首页</button>
        <div className="auth-mark"><Icon name="trophy" size={30} /></div>
        <h1>登录圣杯酱</h1>
        <p className="auth-lead">和同好聊聊最近的新发现</p>
        <form onSubmit={handleSubmit} className="auth-form">
          <label className="field-label" htmlFor="auth-email">邮箱</label>
          <input id="auth-email" className="text-input" type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" autoComplete="email" />
          <label className="field-label" htmlFor="auth-code">邮箱验证码</label>
          <div className="code-field">
            <input id="auth-code" className="text-input" value={code} onChange={(event) => setCode(event.target.value)} placeholder="输入 6 位验证码" inputMode="numeric" maxLength={6} autoComplete="one-time-code" />
            <button type="button" className="code-button" disabled={busy || seconds > 0} onClick={handleRequestCode}>{seconds > 0 ? `${seconds}s 后重发` : "获取验证码"}</button>
          </div>
          {devCode && <div className="dev-code-hint">开发环境验证码：<strong>{devCode}</strong></div>}
          {message && <div className="form-message" role="status">{message}</div>}
          {error && <div className="form-error" role="alert">{error}</div>}
          <button type="submit" className="primary-submit" disabled={busy}>{busy ? "正在进入…" : "登录"}</button>
        </form>
        <div className="auth-divider"><span>或者</span></div>
        <button type="button" className="guest-button" disabled={guestBusy} onClick={handleGuest}>{guestBusy ? "正在创建游客身份…" : "先逛逛，使用游客身份"}</button>
        <p className="auth-footnote">游客可以浏览和评论，登录邮箱账号后才能发布内容。</p>
      </section>
    </main>
  );
}
