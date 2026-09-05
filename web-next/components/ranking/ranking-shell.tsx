"use client";

import React from "react";
import styles from "../../app/ranking/ranking.module.css";

interface RankingDesktopShellProps {
  leftRail?: React.ReactNode;
  children: React.ReactNode;
  rightRail?: React.ReactNode;
  hasRightRail?: boolean;
}

export function RankingDesktopShell({
  leftRail,
  children,
  rightRail,
  hasRightRail = false,
}: RankingDesktopShellProps) {
  const showRight = Boolean(hasRightRail && rightRail);

  return (
    <div className={styles.desktopShell} data-testid="ranking-desktop-shell">
      <div
        className={`${styles.shellGrid} ${!showRight ? styles.noRightRail : ""}`}
        data-testid="ranking-shell-grid"
      >
        {leftRail ? (
          <aside className={styles.leftRail} data-testid="ranking-left-rail">
            {leftRail}
          </aside>
        ) : null}

        <section className={styles.mainCol} data-testid="ranking-main-col">
          {children}
        </section>

        {showRight ? (
          <aside className={styles.rightRail} data-testid="ranking-right-rail">
            {rightRail}
          </aside>
        ) : null}
      </div>
    </div>
  );
}
