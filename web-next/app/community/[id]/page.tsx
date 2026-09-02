import { Suspense } from "react";
import { CommunityShell } from "../../../components/community-shell";

export default async function CommunityPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <Suspense fallback={<main className="page-frame"><div className="loading-stack"><div className="skeleton-card" /><div className="skeleton-card short" /></div></main>}><CommunityShell communityId={id} /></Suspense>;
}
