import { Suspense } from "react";
import { HomeShell } from "../components/home-shell";

export default function HomePage() {
  return <Suspense fallback={<HomeShellFallback />}><HomeShell /></Suspense>;
}

function HomeShellFallback() {
  return <main className="page-frame"><div className="loading-stack"><div className="skeleton-card" /><div className="skeleton-card short" /></div></main>;
}
