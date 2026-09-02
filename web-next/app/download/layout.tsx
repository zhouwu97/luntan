import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "下载圣杯酱 App",
  description: "下载圣杯酱 Android 客户端，体验更完整的社区与榜单。",
};

export default function DownloadLayout({ children }: { children: React.ReactNode }) {
  return children;
}
