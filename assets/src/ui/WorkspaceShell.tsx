import type { ReactNode } from "react";
import { NavRail, type NavDestination } from "./NavRail";
import { SessionActions } from "./SessionActions";

type Props = {
  brand: string;
  children: ReactNode;
  contentClassName: string;
  destinations: readonly NavDestination[];
  eyebrow: string;
  headerActions?: ReactNode;
  navigationLabel: string;
  title: string;
};

export function WorkspaceShell({
  brand,
  children,
  contentClassName,
  destinations,
  eyebrow,
  headerActions,
  navigationLabel,
  title,
}: Props) {
  return (
    <div className="app-shell">
      <NavRail ariaLabel={navigationLabel} brand={brand} items={destinations} />
      <main className="console-frame">
        <header className="topbar">
          <div>
            <p className="product-name">{eyebrow}</p>
            <h1>{title}</h1>
          </div>
          <div className="topbar-actions">
            {headerActions}
            <SessionActions />
          </div>
        </header>
        <div className={contentClassName}>{children}</div>
      </main>
    </div>
  );
}
