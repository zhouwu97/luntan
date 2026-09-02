"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";

const HIDDEN_UNTIL_KEY = "app_download_banner_hidden_until";
const HIDE_DURATION_MS = 7 * 24 * 60 * 60 * 1000;
const SHOW_AFTER_SCROLL_PX = 100;

function readHiddenUntil(): number | null {
  try {
    const raw = window.localStorage.getItem(HIDDEN_UNTIL_KEY);
    if (!raw) return null;
    const value = Number(raw);
    return Number.isFinite(value) && value > Date.now() ? value : null;
  } catch {
    return null;
  }
}

// 首页底部导航上方的轻量 App 下载浮条：仅移动端视口展示，滚动一小段后
// 淡入；关闭后 7 天内不再出现；已安装（standalone）或 App 内嵌 WebView
// 场景一律不推广下载。
export function AppDownloadBanner() {
  const router = useRouter();
  const [eligible, setEligible] = useState(false);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const viewportQuery = window.matchMedia("(max-width: 760px)");
    const standaloneQuery = window.matchMedia("(display-mode: standalone)");
    const evaluate = () => {
      const standalone = standaloneQuery.matches
        || (window.navigator as Navigator & { standalone?: boolean }).standalone === true;
      const inWebView = /;\s*wv\)/.test(window.navigator.userAgent);
      setEligible(viewportQuery.matches && !standalone && !inWebView && readHiddenUntil() === null);
    };
    evaluate();
    viewportQuery.addEventListener("change", evaluate);
    standaloneQuery.addEventListener("change", evaluate);
    return () => {
      viewportQuery.removeEventListener("change", evaluate);
      standaloneQuery.removeEventListener("change", evaluate);
    };
  }, []);

  useEffect(() => {
    if (!eligible) {
      setVisible(false);
      return;
    }
    const onScroll = () => {
      if (window.scrollY > SHOW_AFTER_SCROLL_PX) setVisible(true);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, [eligible]);

  useEffect(() => {
    if (!visible) return;
    document.body.classList.add("app-download-banner-visible");
    return () => document.body.classList.remove("app-download-banner-visible");
  }, [visible]);

  const dismiss = useCallback(() => {
    try {
      window.localStorage.setItem(HIDDEN_UNTIL_KEY, String(Date.now() + HIDE_DURATION_MS));
    } catch {
      // 存储不可用时仅隐藏本次会话
    }
    setVisible(false);
  }, []);

  if (!eligible || !visible) return null;

  return (
    <div className="app-download-banner" role="complementary" aria-label="下载圣杯酱 App">
      <span className="app-download-banner-icon" aria-hidden="true"><Icon name="sparkle" size={20} /></span>
      <span className="app-download-banner-copy">
        <strong>圣杯酱 App</strong>
        <small>体验更完整的社区与榜单</small>
      </span>
      <button type="button" className="app-download-banner-cta" onClick={() => router.push("/download")}>下载</button>
      <button type="button" className="app-download-banner-close" aria-label="7 天内不再显示" onClick={dismiss}>×</button>
    </div>
  );
}
