import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "榜单排序管理 · 圣杯酱",
  robots: { index: false, follow: false },
};

export default function AdminRankingLayout({ children }: { children: React.ReactNode }) {
  return children;
}
