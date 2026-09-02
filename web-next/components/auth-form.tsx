"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { formatError } from "../lib/format";
import { requestEmailCode } from "../lib/api/forum";

type AuthMode = "login" | "register";
type LoginMethod = "code" | "password";

const domainSuggestions = ["@qq.com", "@163.com", "@gmail.com", "@stu..."];

export function AuthForm() {
  const router = useRouter();
  const {
    user,
    signInWithCode,
    signInWithPassword,
    registerWithEmail: createAccount,
    signInAsGuest,
  } = useSession();
  const [mode, setMode] = useState<AuthMode>("login");
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

  useEffect(() => {
    if (seconds <= 0) return;
    const timer = window.setInterval(() => setSeconds((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [seconds]);

  useEffect(() => {
    if (user) router.replace("/");
  }, [router, user]);

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
    if (!email.includes("@")) setEmail(`${email}${domain.replace("...", "")}`);
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
      setSeconds(challenge.retryAfter);
      setDevCode(challenge.devCode || "");
      setMessage(challenge.devCode ? "本地开发验证码已返回，请填写后继续" : "验证码已发送到你的邮箱，10 分钟内有效");
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
      if (!code.trim()) {
        setError("请输入邮箱验证码");
        return;
      }
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
        await createAccount(value, code.trim(), password, nickname.trim());
      } else if (loginMethod === "password") {
        await signInWithPassword(value, password);
      } else {
        await signInWithCode(value, code.trim());
      }
      router.replace("/");
    } catch (requestError) {
      setError(formatError(requestError, mode === "register" ? "注册失败，请检查后重试" : "登录失败，请检查后重试"));
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

  function renderEmailField(id: string, mobile = false) {
    return (
      <>
        <label className="field-label" htmlFor={id}>邮箱</label>
        <div className={`auth-input-shell${mobile ? " auth-mobile-input" : ""}`}>
          {mobile && <Icon name="mail" size={19} />}
          <input
            id={id}
            className="text-input"
            type={mobile ? "text" : "email"}
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder={mobile ? "请输入邮箱" : "you@example.com"}
            autoComplete="email"
          />
          {mobile && email && <button type="button" className="auth-input-clear" aria-label="清空邮箱" onClick={() => setEmail("")}><Icon name="close" size={16} /></button>}
        </div>
        {mobile && email && !email.includes("@") && (
          <div className="email-suggestions" aria-label="邮箱域名建议">
            {domainSuggestions.map((domain) => <button type="button" key={domain} onClick={() => appendDomain(domain)}>{domain}</button>)}
          </div>
        )}
      </>
    );
  }

  function renderCodeField(id: string, mobile = false) {
    return (
      <>
        <label className="field-label" htmlFor={id}>邮箱验证码</label>
        <div className={`code-field${mobile ? " auth-mobile-code-field" : ""}`}>
          {mobile && <Icon name="mail" size={18} />}
          <input id={id} className="text-input" value={code} onChange={(event) => setCode(event.target.value)} placeholder="输入 6 位验证码" inputMode="numeric" maxLength={6} autoComplete="one-time-code" />
          <button type="button" className="code-button" disabled={busy || seconds > 0} onClick={handleRequestCode}>{seconds > 0 ? `${seconds}s 后重发` : "获取验证码"}</button>
        </div>
      </>
    );
  }

  function renderPasswordField(id: string, value: string, setValue: (value: string) => void, visible: boolean, setVisible: (value: boolean) => void, label: string, placeholder = "请输入密码") {
    return (
      <>
        <label className="field-label" htmlFor={id}>{label}</label>
        <div className="auth-input-shell auth-mobile-input">
          <Icon name="lock" size={19} />
          <input id={id} className="text-input" type={visible ? "text" : "password"} value={value} onChange={(event) => setValue(event.target.value)} placeholder={placeholder} autoComplete={label === "确认密码" ? "new-password" : "current-password"} />
          <button type="button" className="auth-input-toggle" aria-label={visible ? "隐藏密码" : "显示密码"} onClick={() => setVisible(!visible)}><Icon name={visible ? "eye" : "eye-off"} size={19} /></button>
        </div>
      </>
    );
  }

  function renderFeedback() {
    return <>{devCode && <div className="dev-code-hint">开发环境验证码：<strong>{devCode}</strong></div>}{message && <div className="form-message" role="status">{message}</div>}{error && <div className="form-error" role="alert">{error}</div>}</>;
  }

  return (
    <main className="auth-page">
      <div className="auth-glow auth-glow-one" />
      <div className="auth-glow auth-glow-two" />
      <div className="auth-mobile-top">
        <button type="button" aria-label="关闭登录页" onClick={() => router.push("/")}><Icon name="close" size={21} /></button>
        <button type="button" className="auth-permission-button" onClick={() => setPermissionOpen((value) => !value)}><Icon name="info" size={15} />权限说明</button>
        {permissionOpen && <div className="auth-permission-note">登录后才可以发布内容，浏览和评论无需登录。</div>}
      </div>
      <section className="auth-card">
        <div className="auth-desktop-flow">
          <button type="button" className="back-link" onClick={() => router.push("/")}><Icon name="chevron-left" size={17} />返回首页</button>
          <div className="auth-mark"><Icon name="trophy" size={30} /></div>
          <h1>登录圣杯酱</h1>
          <p className="auth-lead">和同好聊聊最近的新发现</p>
          <form onSubmit={handleSubmit} className="auth-form">
            {renderEmailField("desktop-auth-email")}
            {renderCodeField("desktop-auth-code")}
            {renderFeedback()}
            <button type="submit" className="primary-submit" disabled={busy}>{busy ? "正在进入…" : "登录"}</button>
          </form>
          <div className="auth-divider"><span>或者</span></div>
          <button type="button" className="guest-button" disabled={guestBusy} onClick={handleGuest}>{guestBusy ? "正在创建游客身份…" : "先逛逛，使用游客身份"}</button>
          <p className="auth-footnote">游客可以浏览和评论，登录邮箱账号后才能发布内容。</p>
        </div>

        <div className="auth-mobile-flow">
          <div className="auth-mobile-card-header">
            <div className="auth-mobile-app-mark"><Icon name="message" size={25} /></div>
            <div><h1>欢迎来到圣杯酱</h1><p>登录账号或创建新的账号</p></div>
          </div>
          <div className="auth-mode-tabs" role="tablist" aria-label="登录或注册">
            <button type="button" className={mode === "login" ? "active" : ""} onClick={() => changeMode("login")}>登录</button>
            <button type="button" className={mode === "register" ? "active" : ""} onClick={() => changeMode("register")}>注册</button>
          </div>
          {mode === "login" && (
            <div className="auth-method-tabs" role="tablist" aria-label="登录方式">
              <button type="button" className={loginMethod === "code" ? "active" : ""} onClick={() => changeLoginMethod("code")}>验证码登录</button>
              <button type="button" className={loginMethod === "password" ? "active" : ""} onClick={() => changeLoginMethod("password")}>密码登录</button>
            </div>
          )}
          <form onSubmit={handleSubmit} className="auth-form auth-mobile-form">
            {renderEmailField("mobile-auth-email", true)}
            {mode === "register" && renderCodeField("mobile-auth-code", true)}
            {mode === "register" && renderPasswordField("mobile-auth-password", password, setPassword, showPassword, setShowPassword, "设置密码", "至少 8 位密码")}
            {mode === "register" && renderPasswordField("mobile-auth-confirm-password", confirmPassword, setConfirmPassword, showConfirmPassword, setShowConfirmPassword, "确认密码", "再次输入密码")}
            {mode === "register" && <><label className="field-label" htmlFor="mobile-auth-nickname">昵称（选填）</label><input id="mobile-auth-nickname" className="text-input" value={nickname} onChange={(event) => setNickname(event.target.value)} placeholder="给自己取个昵称" autoComplete="nickname" /></>}
            {mode === "login" && loginMethod === "code" && renderCodeField("mobile-auth-login-code", true)}
            {mode === "login" && loginMethod === "password" && renderPasswordField("mobile-auth-login-password", password, setPassword, showPassword, setShowPassword, "密码")}
            {mode === "login" && loginMethod === "password" && <button type="button" className="auth-forgot" onClick={() => changeLoginMethod("code")}>忘记密码？使用验证码登录</button>}
            {renderFeedback()}
            <button type="submit" className="primary-submit" disabled={busy}>{busy ? (mode === "register" ? "正在注册…" : "正在登录…") : mode === "register" ? "注册并进入论坛" : "登录"}</button>
          </form>
        </div>
      </section>
      <div className="auth-mobile-extra">
        <button type="button" className="guest-button" disabled={guestBusy} onClick={handleGuest}><Icon name="eye" size={17} />{guestBusy ? "正在创建游客身份…" : "暂不登录，以游客身份体验"}</button>
        <button type="button" className="auth-browse-link" onClick={() => router.push("/")}>返回浏览公开帖子</button>
      </div>
    </main>
  );
}
