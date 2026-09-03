"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";

const HIDDEN_UNTIL_KEY = "app_download_banner_hidden_until";
const HIDE_DURATION_MS = 3 * 24 * 60 * 60 * 1000;

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

// 底部导航栏上方的轻量 App 下载浮窗：在移动端及 Web 视口保持呈现；
// 已安装（standalone）或 App 内嵌 WebView 场景不重复推广。
export function AppDownloadBanner({ className = "" }: { className?: string }) {
  const router = useRouter();
  const [mounted, setMounted] = useState(false);
  const [closed, setClosed] = useState(false);

  useEffect(() => {
    const standaloneQuery = window.matchMedia("(display-mode: standalone)");
    const standalone = standaloneQuery.matches
      || (window.navigator as Navigator & { standalone?: boolean }).standalone === true;
    const inWebView = /;\s*wv\)/.test(window.navigator.userAgent);
    const hidden = readHiddenUntil() !== null;
    if (!standalone && !inWebView && !hidden) {
      setMounted(true);
    }
  }, []);

  const dismiss = useCallback(() => {
    try {
      window.localStorage.setItem(HIDDEN_UNTIL_KEY, String(Date.now() + HIDE_DURATION_MS));
    } catch {
      // 存储不可用时仅隐藏本次会话
    }
    setClosed(true);
  }, []);

  if (!mounted || closed) return null;

  return (
    <div className={`app-download-banner ${className}`.trim()} role="complementary" aria-label="下载圣杯酱 App">
      <span className="app-download-banner-icon" aria-hidden="true">
        <Icon name="sparkle" size={20} />
      </span>
      <span className="app-download-banner-copy">
        <strong>圣杯酱 App</strong>
        <small>体验更完整的社区与榜单</small>
      </span>
      <button
        type="button"
        className="app-download-banner-cta"
        onClick={() => router.push("/download")}
      >
        下载
      </button>
      <button
        type="button"
        className="app-download-banner-close"
        aria-label="关闭提示"
        onClick={dismiss}
      >
        ×
      </button>
    </div>
  );
}
