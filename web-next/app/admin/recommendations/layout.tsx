import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "首页推荐管理 · 圣杯酱",
  robots: { index: false, follow: false },
};

export default function AdminRecommendationsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
