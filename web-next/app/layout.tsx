import type { Metadata, Viewport } from "next";
import { Suspense } from "react";
import "./globals.css";
import { SessionProvider } from "../components/session-provider";
import { ToastProvider } from "../components/toast-context";

export const metadata: Metadata = {
  title: "圣杯酱 · 玩具交流轻社区",
  description: "分享设备、桌搭、校园生活和真实使用体验。",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN" data-scroll-behavior="smooth">
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
