import type { Metadata, Viewport } from "next";
import { Suspense } from "react";
import "./globals.css";
import { SessionProvider } from "../components/session-provider";
import { ToastProvider } from "../components/toast-context";
import { publicSiteOrigin } from "../lib/public-site";

export const metadata: Metadata = {
  metadataBase: new URL(`${publicSiteOrigin}/`),
  title: "圣杯酱 · 玩具交流轻社区",
  description: "分享设备、桌搭、校园生活和真实使用体验。",
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/favicon.png", type: "image/png", sizes: "192x192" },
      { url: "/apple-icon.png", type: "image/png", sizes: "180x180" },
    ],
    shortcut: "/apple-icon.png",
    apple: [{ url: "/apple-icon.png", sizes: "180x180", type: "image/png" }],
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN" data-scroll-behavior="smooth" suppressHydrationWarning>
      <body>
        <SessionProvider>
          <ToastProvider>
            <Suspense
              fallback={
                <div className="page-frame">
                  <div className="loading-stack">
                    <div className="skeleton-card short" />
                  </div>
                </div>
              }
            >
              {children}
            </Suspense>
          </ToastProvider>
        </SessionProvider>
      </body>
    </html>
  );
}
