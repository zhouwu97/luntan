"use client";

import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { AuthSession, SessionUser } from "../types/forum";
import { getMe, getUnreadNotificationCount, loginAsGuest, loginWithEmailCode, loginWithPassword, logout, registerWithEmail } from "../lib/api/forum";
import { refreshSession } from "../lib/api/client";

interface SessionContextValue {
  user: SessionUser | null;
  ready: boolean;
  unreadCount: number;
  refreshUnreadCount: () => Promise<void>;
  signInWithCode: (email: string, code: string) => Promise<void>;
  signInWithPassword: (email: string, password: string) => Promise<void>;
  registerWithEmail: (email: string, code: string, password: string, nickname?: string) => Promise<void>;
  signInAsGuest: () => Promise<void>;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<SessionUser | null>(null);
  const [ready, setReady] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);

  useEffect(() => {
    let active = true;
    void refreshSession()
      .then(async (restored) => {
        if (!restored) return;
        const currentUser = await getMe();
        if (!active) return;
        setUser(currentUser);
        void getUnreadNotificationCount().then((count) => {
          if (active) setUnreadCount(count);
        }).catch(() => undefined);
      })
      .catch(() => undefined)
      .finally(() => {
        if (active) setReady(true);
      });
    return () => {
      active = false;
    };
  }, []);

  const value = useMemo<SessionContextValue>(
    () => ({
      user,
      ready,
      unreadCount,
      refreshUnreadCount: async () => {
        try {
          setUnreadCount(await getUnreadNotificationCount());
        } catch {
          // 网络不可用时保留当前角标，避免误报为已读。
        }
      },
      signInWithCode: async (email, code) => {
        const session: AuthSession = await loginWithEmailCode(email, code);
        setUser(session.user);
        void getUnreadNotificationCount().then(setUnreadCount).catch(() => setUnreadCount(0));
      },
      signInWithPassword: async (email, password) => {
        const session: AuthSession = await loginWithPassword(email, password);
        setUser(session.user);
        void getUnreadNotificationCount().then(setUnreadCount).catch(() => setUnreadCount(0));
      },
      registerWithEmail: async (email, code, password, nickname) => {
        const session: AuthSession = await registerWithEmail(email, code, password, nickname);
        setUser(session.user);
        void getUnreadNotificationCount().then(setUnreadCount).catch(() => setUnreadCount(0));
      },
      signInAsGuest: async () => {
        const session: AuthSession = await loginAsGuest();
        setUser(session.user);
        setUnreadCount(0);
      },
      signOut: async () => {
        await logout();
        setUser(null);
        setUnreadCount(0);
      },
    }),
    [ready, unreadCount, user],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("useSession 必须在 SessionProvider 内使用");
  return value;
}
