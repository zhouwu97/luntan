"use client";

import { createContext, useContext, useEffect, useMemo, useRef, useState } from "react";
import type { AuthSession, SessionUser } from "../types/forum";
import {
  getMe,
  getUnreadNotificationCount,
  loginAsGuest,
  loginWithEmailCode,
  loginWithPassword,
  logout,
  registerWithEmail,
} from "../lib/api/forum";
import { refreshSession } from "../lib/api/client";
import { clearFeedCache } from "../lib/feed-cache";
import { clearPostSnapshots } from "../lib/post-memory-cache";

export type AuthState = "anonymous" | "guest" | "registered";

interface SessionContextValue {
  user: SessionUser | null;
  ready: boolean;
  authState: AuthState;
  isGuest: boolean;
  isRegistered: boolean;
  unreadCount: number;
  refreshUnreadCount: () => Promise<void>;
  signInWithCode: (email: string, code: string) => Promise<void>;
  signInWithPassword: (email: string, password: string) => Promise<void>;
  registerWithEmail: (email: string, password: string, code?: string, nickname?: string) => Promise<void>;
  signInAsGuest: () => Promise<void>;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<SessionUser | null>(null);
  const [ready, setReady] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const unreadAccount = useRef<string | undefined>(undefined);

  useEffect(() => {
    let active = true;
    void refreshSession()
      .then(async (restored) => {
        if (!restored) {
          try {
            const guestSession = await loginAsGuest();
            if (active) setUser(guestSession.user);
          } catch {
            // 离线或后端服务不可用时保持 anonymous
          }
          return;
        }
        const currentUser = await getMe();
        if (!active) return;
        setUser(currentUser);

      })
      .catch(() => undefined)
      .finally(() => {
        if (active) setReady(true);
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    let active = true;
    let pending = false;
    unreadAccount.current = user?.id;
    setUnreadCount(0);
    const refresh = async () => {
      if (!user || document.visibilityState !== "visible" || pending) return;
      pending = true;
      try {
        const count = await getUnreadNotificationCount();
        if (active) setUnreadCount(count);
      } catch {
        // 轮询失败保留当前角标，下一次前台刷新重试。
      } finally {
        pending = false;
      }
    };
    void refresh();
    const timer = window.setInterval(() => void refresh(), 30000);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, [user?.id]);

  const isGuest = Boolean(user && user.accountType === "guest");
  const isRegistered = Boolean(user && user.accountType !== "guest");
  const authState: AuthState = !user ? "anonymous" : isGuest ? "guest" : "registered";

  const value = useMemo<SessionContextValue>(
    () => ({
      user,
      ready,
      authState,
      isGuest,
      isRegistered,
      unreadCount,
      refreshUnreadCount: async () => {
        try {
          const count = await getUnreadNotificationCount();
          if (user?.id === unreadAccount.current) setUnreadCount(count);
        } catch {
          // 网络不可用时保留当前角标，避免误报为已读。
        }
      },
      signInWithCode: async (email, code) => {
        const session: AuthSession = await loginWithEmailCode(email, code);
        setUser(session.user);
      },
      signInWithPassword: async (email, password) => {
        const session: AuthSession = await loginWithPassword(email, password);
        setUser(session.user);
      },
      registerWithEmail: async (email, password, code, nickname) => {
        const session: AuthSession = await registerWithEmail(email, password, code, nickname);
        setUser(session.user);
      },
      signInAsGuest: async () => {
        const session: AuthSession = await loginAsGuest();
        setUser(session.user);
        setUnreadCount(0);
      },
      signOut: async () => {
        const accountScope = user?.id;
        await logout();
        clearFeedCache(accountScope);
        clearPostSnapshots(accountScope);
        setUnreadCount(0);
        try {
          const guestSession = await loginAsGuest();
          setUser(guestSession.user);
        } catch {
          setUser(null);
        }
      },
    }),
    [authState, isGuest, isRegistered, ready, unreadCount, user],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("useSession 必须在 SessionProvider 内使用");
  return value;
}
