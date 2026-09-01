import type { Metadata } from "next";
import "./globals.css";
import { SessionProvider } from "../components/session-provider";

export const metadata: Metadata = {
  title: "圣杯酱 · 玩具交流轻社区",
  description: "分享设备、桌搭、校园生活和真实使用体验。",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN" data-scroll-behavior="smooth"><body><SessionProvider>{children}</SessionProvider></body></html>;
}
