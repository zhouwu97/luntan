"use client";

import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import { Icon } from "./icons";

export function MobilePageHeader({ title, action }: { title: string; action?: ReactNode }) {
  const router = useRouter();

  return (
    <header className="mobile-page-header">
      <button type="button" aria-label="返回首页" onClick={() => router.push("/")}>
        <Icon name="chevron-left" size={20} />
      </button>
      <h1>{title}</h1>
      <span className="mobile-page-header-action">{action}</span>
    </header>
  );
}
