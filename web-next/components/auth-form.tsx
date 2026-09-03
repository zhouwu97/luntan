"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { formatError } from "../lib/format";
import { requestEmailCode } from "../lib/api/forum";

type AuthMode = "login" | "register";
type LoginMethod = "password" | "code";

const domainSuggestions = ["@qq.com", "@163.com", "@gmail.com", "@outlook.com"];

function safeNext(value: string | null) {
  if (!value || value.startsWith("//") || !value.startsWith("/")) return "/";
  return value;
}

export function AuthForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const {
    user,
    signInWithCode,
    signInWithPassword,
    registerWithEmail: createAccount,
    signInAsGuest,
  } = useSession();

  const initialMode = searchParams.get("mode") === "register" ? "register" : "login";
  const [mode, setMode] = useState<AuthMode>(initialMode);
  const [loginMethod, setLoginMethod] = useState<LoginMethod>("password");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [nickname, setNickname] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [devCode, setDevCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [guestBusy, setGuestBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [permissionOpen, setPermissionOpen] = useState(false);
  const destination = safeNext(searchParams.get("next"));

  useEffect(() => {
    if (seconds <= 0) return;
    const timer = window.setInterval(() => setSeconds((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [seconds]);

  useEffect(() => {
    if (user) router.replace(destination);
  }, [destination, router, user]);

  function clearFeedback() {
    setError("");
    setMessage("");
    setDevCode("");
  }

  function changeMode(nextMode: AuthMode) {
    setMode(nextMode);
    setLoginMethod("password");
    clearFeedback();
  }

  function changeLoginMethod(nextMethod: LoginMethod) {
    setLoginMethod(nextMethod);
    clearFeedback();
  }

  function appendDomain(domain: string) {
    if (!email.includes("@")) setEmail(`${email}${domain}`);
  }

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
      const challenge = await requestEmailCode(value, mode === "register" ? "register" : "login");
      setSeconds(challenge.retryAfter || 60);
      setDevCode(challenge.devCode || "");
      setMessage(
        challenge.devCode
          ? "本地开发验证码已返回，请填写后继续"
          : "验证码已发送到你的邮箱，10 分钟内有效",
      );
    } catch (requestError) {
      setError(formatError(requestError, "验证码发送失败，请稍后再试"));
    } finally {
      setBusy(false);
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const value = email.trim();
    if (!/^\S+@\S+\.\S+$/.test(value)) {
      setError("请输入有效的邮箱地址");
      return;
    }

    if (mode === "register") {
      if (password.length < 8) {
        setError("密码至少需要 8 位");
        return;
      }
      if (password !== confirmPassword) {
        setError("两次输入的密码不一致");
        return;
      }
    } else if (loginMethod === "code") {
      if (!code.trim()) {
        setError("请填写邮箱验证码");
        return;
      }
    } else if (!password) {
      setError("请输入密码");
      return;
    }

    setBusy(true);
    setError("");
    try {
      if (mode === "register") {
        await createAccount(value, password, code.trim() || undefined, nickname.trim());
      } else if (loginMethod === "password") {
        await signInWithPassword(value, password);
      } else {
        await signInWithCode(value, code.trim());
      }
      router.replace(destination);
    } catch (requestError: unknown) {
      const formatted = formatError(
        requestError,
        mode === "register" ? "注册失败，请检查后重试" : "登录失败，请检查后重试",
      );
      if (formatted.includes("INVALID_EMAIL_CODE") || formatted.includes("验证码无效")) {
        setError("邮箱验证码错误或已过期，请重新获取");
      } else if (formatted.includes("EMAIL_ALREADY_REGISTERED")) {
        setError("该邮箱已注册，请直接切换为登录");
      } else if (formatted.includes("EMAIL_NOT_REGISTERED")) {
        setError("该邮箱尚未注册，请先点击上方“注册”创建账号");
      } else {
        setError(formatted);
      }
    } finally {
      setBusy(false);
    }
  }

  async function handleGuest() {
    setGuestBusy(true);
    setError("");
    try {
      await signInAsGuest();
      router.replace(destination);
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

      {/* 顶部简易导航 / 权限说明 */}
      <div className="auth-mobile-top">
        <button type="button" aria-label="关闭登录页" onClick={() => router.push("/")}>
          <Icon name="close" size={21} />
        </button>
        <button
          type="button"
          className="auth-permission-button"
          onClick={() => setPermissionOpen((value) => !value)}
        >
          <Icon name="info" size={15} />
          权限说明
        </button>
        {permissionOpen && (
          <div className="auth-permission-note">
            登录后才可以发布内容与收藏，浏览和评论无需登录。
          </div>
        )}
      </div>

      <section className="auth-card">
        {/* 返回按钮与品牌徽标 */}
        <button type="button" className="back-link desktop-only" onClick={() => router.push("/")}>
          <Icon name="chevron-left" size={17} />
          返回首页
        </button>

        <div className="auth-card-brand">
          <div className="auth-mark">
            <Icon name="trophy" size={28} />
          </div>
          <h1>{mode === "register" ? "注册圣杯酱账号" : "登录圣杯酱"}</h1>
          <p className="auth-lead">
            {mode === "register"
              ? "加入胶佬同好聚集地，分享真实拆箱与测评"
              : "和同好聊聊最近的新发现"}
          </p>
        </div>

        {/* 模式切换 Tabs（登录 / 注册） */}
        <div className="auth-mode-tabs" role="tablist" aria-label="登录或注册">
          <button
            type="button"
            className={mode === "login" ? "active" : ""}
            onClick={() => changeMode("login")}
          >
            登录
          </button>
          <button
            type="button"
            className={mode === "register" ? "active" : ""}
            onClick={() => changeMode("register")}
          >
            注册
          </button>
        </div>

        {/* 登录方式切换 Tabs（密码登录 / 验证码登录） */}
        {mode === "login" && (
          <div className="auth-method-tabs" role="tablist" aria-label="登录方式">
            <button
              type="button"
              className={loginMethod === "password" ? "active" : ""}
              onClick={() => changeLoginMethod("password")}
            >
              密码登录
            </button>
            <button
              type="button"
              className={loginMethod === "code" ? "active" : ""}
              onClick={() => changeLoginMethod("code")}
            >
              验证码登录
            </button>
          </div>
        )}

        {/* 统一单套响应式表单 DOM */}
        <form onSubmit={handleSubmit} className="auth-form">
          {/* 邮箱字段 */}
          <div className="auth-field-group">
            <label className="field-label" htmlFor="auth-email">
              邮箱
            </label>
            <div className="auth-input-shell">
              <Icon name="mail" size={18} />
              <input
                id="auth-email"
                className="text-input"
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="请输入邮箱地址"
                autoComplete="email"
                required
              />
              {email && (
                <button
                  type="button"
                  className="auth-input-clear"
                  aria-label="清空邮箱"
                  onClick={() => setEmail("")}
                >
                  <Icon name="close" size={15} />
                </button>
              )}
            </div>
            {email && !email.includes("@") && (
              <div className="email-suggestions" aria-label="邮箱域名建议">
                {domainSuggestions.map((domain) => (
                  <button type="button" key={domain} onClick={() => appendDomain(domain)}>
                    {domain}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* 登录 - 密码输入 */}
          {mode === "login" && loginMethod === "password" && (
            <div className="auth-field-group">
              <label className="field-label" htmlFor="auth-login-password">
                密码
              </label>
              <div className="auth-input-shell">
                <Icon name="lock" size={18} />
                <input
                  id="auth-login-password"
                  className="text-input"
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  placeholder="请输入密码"
                  autoComplete="current-password"
                  required
                />
                <button
                  type="button"
                  className="auth-input-toggle"
                  aria-label={showPassword ? "隐藏密码" : "显示密码"}
                  onClick={() => setShowPassword(!showPassword)}
                >
                  <Icon name={showPassword ? "eye" : "eye-off"} size={18} />
                </button>
              </div>
              <button
                type="button"
                className="auth-forgot"
                onClick={() => changeLoginMethod("code")}
              >
                忘记密码？使用验证码登录
              </button>
            </div>
          )}

          {/* 登录 - 验证码输入 */}
          {mode === "login" && loginMethod === "code" && (
            <div className="auth-field-group">
              <label className="field-label" htmlFor="auth-login-code">
                邮箱验证码
              </label>
              <div className="code-field">
                <Icon name="mail" size={18} />
                <input
                  id="auth-login-code"
                  className="text-input"
                  value={code}
                  onChange={(event) => setCode(event.target.value)}
                  placeholder="输入 6 位验证码"
                  inputMode="numeric"
                  maxLength={6}
                  autoComplete="one-time-code"
                  required
                />
                <button
                  type="button"
                  className="code-button"
                  disabled={busy || seconds > 0}
                  onClick={handleRequestCode}
                >
                  {seconds > 0 ? `${seconds}s 后重发` : "获取验证码"}
                </button>
              </div>
            </div>
          )}

          {/* 注册 - 设置密码 */}
          {mode === "register" && (
            <>
              <div className="auth-field-group">
                <label className="field-label" htmlFor="auth-reg-password">
                  设置密码
                </label>
                <div className="auth-input-shell">
                  <Icon name="lock" size={18} />
                  <input
                    id="auth-reg-password"
                    className="text-input"
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                    placeholder="至少 8 位密码"
                    autoComplete="new-password"
                    required
                  />
                  <button
                    type="button"
                    className="auth-input-toggle"
                    aria-label={showPassword ? "隐藏密码" : "显示密码"}
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    <Icon name={showPassword ? "eye" : "eye-off"} size={18} />
                  </button>
                </div>
              </div>

              <div className="auth-field-group">
                <label className="field-label" htmlFor="auth-reg-confirm-password">
                  确认密码
                </label>
                <div className="auth-input-shell">
                  <Icon name="lock" size={18} />
                  <input
                    id="auth-reg-confirm-password"
                    className="text-input"
                    type={showConfirmPassword ? "text" : "password"}
                    value={confirmPassword}
                    onChange={(event) => setConfirmPassword(event.target.value)}
                    placeholder="再次输入密码"
                    autoComplete="new-password"
                    required
                  />
                  <button
                    type="button"
                    className="auth-input-toggle"
                    aria-label={showConfirmPassword ? "隐藏密码" : "显示密码"}
                    onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                  >
                    <Icon name={showConfirmPassword ? "eye" : "eye-off"} size={18} />
                  </button>
                </div>
              </div>

              <div className="auth-field-group">
                <label className="field-label" htmlFor="auth-reg-nickname">
                  昵称（选填）
                </label>
                <div className="auth-input-shell">
                  <Icon name="user" size={18} />
                  <input
                    id="auth-reg-nickname"
                    className="text-input"
                    value={nickname}
                    onChange={(event) => setNickname(event.target.value)}
                    placeholder="给自己取个昵称"
                    autoComplete="nickname"
                  />
                </div>
              </div>

              <div className="auth-field-group">
                <div className="field-label-row">
                  <label className="field-label" htmlFor="auth-reg-code">
                    邮箱验证码（选填）
                  </label>
                  <span className="field-hint">当前支持免验证码直接注册</span>
                </div>
                <div className="code-field">
                  <Icon name="mail" size={18} />
                  <input
                    id="auth-reg-code"
                    className="text-input"
                    value={code}
                    onChange={(event) => setCode(event.target.value)}
                    placeholder="若收到验证码可填，无则留空"
                    inputMode="numeric"
                    maxLength={6}
                    autoComplete="one-time-code"
                  />
                  <button
                    type="button"
                    className="code-button"
                    disabled={busy || seconds > 0}
                    onClick={handleRequestCode}
                  >
                    {seconds > 0 ? `${seconds}s 后重发` : "获取验证码"}
                  </button>
                </div>
              </div>
            </>
          )}

          {/* 错误与状态提示 */}
          {devCode && (
            <div className="dev-code-hint">
              开发环境验证码：<strong>{devCode}</strong>
            </div>
          )}
          {message && (
            <div className="form-message" role="status">
              {message}
            </div>
          )}
          {error && (
            <div className="form-error" role="alert">
              {error}
            </div>
          )}

          {/* 提交按钮 */}
          <button type="submit" className="primary-submit" disabled={busy}>
            {busy
              ? mode === "register"
                ? "正在注册…"
                : "正在登录…"
              : mode === "register"
              ? "注册并进入社区"
              : "登录"}
          </button>
        </form>

        {/* 分隔线与游客登录 */}
        <div className="auth-divider">
          <span>或者</span>
        </div>
        <button
          type="button"
          className="guest-button"
          disabled={guestBusy}
          onClick={handleGuest}
        >
          <Icon name="eye" size={17} />
          {guestBusy ? "正在创建游客身份…" : "先逛逛，使用游客身份体验"}
        </button>
        <p className="auth-footnote">
          游客可以浏览和评论，注册邮箱账号后可解锁等级、发帖与收藏。
        </p>
      </section>
    </main>
  );
}
