import type { ReactNode } from "react";
import { NavRail } from "../../ui/NavRail";

type Props = {
  detail: ReactNode;
  inbox: ReactNode;
  inspector: ReactNode;
};

export function OperatorLayout({ detail, inbox, inspector }: Props) {
  return (
    <div className="app-shell">
      <NavRail
        ariaLabel="Operator sections"
        brand="OG"
        items={[
          { label: "Inbox", state: "current" },
          { label: "My Queue", state: "unavailable" },
          { label: "All Runs", state: "unavailable" },
          { label: "Entities", state: "unavailable" },
          { label: "Reports", state: "unavailable" }
        ]}
      />
      <main className="console-frame">
        <header className="topbar">
          <div>
            <p className="product-name">Office Graph</p>
            <h1>Operator Console</h1>
          </div>
          <div className="search-box">
            <input aria-label="Search operator work" disabled placeholder="Search unavailable" />
          </div>
        </header>
        <div className="workbench">
          {inbox}
          {detail}
          <div className="inspector-stack">{inspector}</div>
        </div>
      </main>
    </div>
  );
}
