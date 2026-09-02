"use client";

import { useEffect, useState } from "react";
import { SiteHeader } from "../../components/site-header";
import { Icon } from "../../components/icons";
import { apiJson } from "../../lib/api/client";
import { formatError } from "../../lib/format";
import { resolveAssetUrl } from "../../lib/config";

interface AppReleaseInfo {
  latest_version_name?: string;
  file_size?: number;
  sha256?: string;
  changelog?: string;
  published_at?: string;
  download_url?: string;
}

function formatBytes(value: unknown): string {
  const size = Number(value);
  if (!Number.isFinite(size) || size <= 0) return "—";
  const units = ["B", "KB", "MB", "GB"];
  let scaled = size;
  let unit = 0;
  while (scaled >= 1024 && unit < units.length - 1) {
    scaled /= 1024;
    unit += 1;
  }
  return `${scaled >= 100 ? scaled.toFixed(0) : scaled >= 10 ? scaled.toFixed(1) : scaled.toFixed(2)} ${units[unit]}`;
}

function formatDate(value: unknown): string {
  const date = new Date(String(value || ""));
  return Number.isNaN(date.getTime())
    ? "—"
    : new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}

export default function DownloadPage() {
  const [release, setRelease] = useState<AppReleaseInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    void apiJson<AppReleaseInfo>("/app/releases/latest")
      .then((info) => {
        if (active) setRelease(info);
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "版本信息暂时无法获取，请稍后再试"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const downloadUrl = resolveAssetUrl(release?.download_url);
  const changelog = (release?.changelog || "").trim();

  return (
    <>
      <SiteHeader />
      <main className="page-frame download-page">
        <section className="download-hero">
          <span className="download-app-icon" aria-hidden="true"><Icon name="download" size={26} /></span>
          <h1>把圣杯酱装进手机</h1>
          <p>Android 客户端与网页使用同一账号体系，消息提醒更及时，浏览社区与榜单也更顺畅。</p>
        </section>
        {loading && <div className="download-state" role="status">正在读取版本信息…</div>}
        {!loading && error && (
          <div className="download-state" role="status">
            {error}
            <button type="button" className="download-retry" onClick={() => window.location.reload()}>重新获取</button>
          </div>
        )}
        {!loading && !error && release && (
          <>
            <section className="download-card" aria-label="安装包信息">
              <div className="download-metrics">
                <div className="download-metric"><span>版本</span><strong>v{release.latest_version_name || "—"}</strong></div>
                <div className="download-metric"><span>安装包大小</span><strong>{formatBytes(release.file_size)}</strong></div>
                <div className="download-metric"><span>发布时间</span><strong>{formatDate(release.published_at)}</strong></div>
              </div>
              {changelog && <div className="download-changelog"><span>更新说明</span><p>{changelog}</p></div>}
              {downloadUrl ? (
                <a className="download-button" href={downloadUrl}><Icon name="download" size={18} />下载 Android APK</a>
              ) : (
                <div className="download-unavailable">安装包暂未开放下载，请稍后再来。</div>
              )}
              {release.sha256 && <p className="download-sha">SHA-256 · {release.sha256}</p>}
            </section>
            <section className="download-notes" aria-label="安装提示">
              <div className="download-note"><strong>与软件内更新一致</strong><p>这里和 App 内“检查更新”读取同一个发布源，版本不会出现不一致。</p></div>
              <div className="download-note"><strong>安装提示</strong><p>首次通过浏览器安装 APK 时，Android 可能会要求允许来自此来源的应用安装，同意后继续即可。</p></div>
              <div className="download-note"><strong>以后会有更多入口</strong><p>应用商店与 iOS 版本上线后会直接出现在本页，无需再找新地址。</p></div>
            </section>
          </>
        )}
      </main>
    </>
  );
}
