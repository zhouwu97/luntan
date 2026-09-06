"use client";

import { useEffect, useState } from "react";

/**
 * 让会改变数据请求的响应式逻辑和 CSS 断点共用同一套判断，避免只隐藏 UI 却仍挂载桌面组件。
 */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const mediaQuery = window.matchMedia(query);
    const update = () => setMatches(mediaQuery.matches);
    update();

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", update);
      return () => mediaQuery.removeEventListener("change", update);
    }

    mediaQuery.addListener(update);
    return () => mediaQuery.removeListener(update);
  }, [query]);

  return matches;
}
