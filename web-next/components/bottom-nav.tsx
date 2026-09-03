"use client";

import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import { useSession } from "./session-provider";

export function BottomNav({
  activeNav = "home",
}: {
  activeNav?: "home" | "profile";
}) {
  const router = useRouter();
  const { user } = useSession();

  return (
    <nav className="bottom-nav" aria-label="底部导航">
      <button
        type="button"
        className={`nav-item${activeNav === "home" ? " active" : ""}`}
        onClick={() => router.push("/")}
      >
        <Icon name="home" size={22} />
        <span>首页</span>
      </button>

      <button
        type="button"
        className="publish-fab"
        aria-label="发布"
        onClick={() => {
          if (!user) {
            router.push(`/login?next=${encodeURIComponent("/publish")}`);
          } else {
            router.push("/publish");
          }
        }}
      >
        <Icon name="plus" size={26} strokeWidth={2.2} />
      </button>

      <button
        type="button"
        className={`nav-item${activeNav === "profile" ? " active" : ""}`}
        onClick={() => router.push(user ? "/me" : "/login")}
      >
        <Icon name="user" size={22} />
        <span>我的</span>
      </button>
    </nav>
  );
}
