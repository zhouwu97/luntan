import { Suspense } from "react";
import { RankingDetailShell } from "../../../components/ranking-detail-shell";

export default async function RankingDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <Suspense fallback={<main className="page-frame"><div className="loading-stack"><div className="skeleton-card" /><div className="skeleton-card short" /></div></main>}><RankingDetailShell id={decodeURIComponent(id)} /></Suspense>;
}
