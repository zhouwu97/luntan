"use client";

import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { AuthSession, SessionUser } from "../types/forum";
import { getMe, loginAsGuest, loginWithEmailCode, logout } from "../lib/api/forum";
import { refreshSession } from "../lib/api/client";

interface SessionContextValue {
  user: SessionUser | null;
  ready: boolean;
  signInWithCode: (email: string, code: string) => Promise<void>;
  signInAsGuest: () => Promise<void>;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<SessionUser | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let active = true;
    void refreshSession()
      .then(async (restored) => {
        if (!restored) return;
        const currentUser = await getMe();
        if (active) setUser(currentUser);
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
      signInWithCode: async (email, code) => {
        const session: AuthSession = await loginWithEmailCode(email, code);
        setUser(session.user);
      },
      signInAsGuest: async () => {
        const session: AuthSession = await loginAsGuest();
        setUser(session.user);
      },
      signOut: async () => {
        await logout();
        setUser(null);
      },
    }),
    [ready, user],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("useSession 必须在 SessionProvider 内使用");
  return value;
}
