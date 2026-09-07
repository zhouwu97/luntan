import type { Metadata } from "next";
import Link from "next/link";
import { SiteHeader } from "../../components/site-header";

export const metadata: Metadata = {
  title: "帖子不存在 - 圣杯酱",
  robots: { index: false, follow: false },
};

export default function PostNotFoundPage() {
  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <div className="empty-state">
          <h1>帖子不存在</h1>
          <p>这条帖子可能已被删除，或链接不正确。</p>
          <Link className="primary-link" href="/">返回首页</Link>
        </div>
      </main>
    </>
  );
}
