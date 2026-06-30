import type { ReactNode } from "react";
import { NavRail } from "../ui/NavRail";

type Props = {
  detail: ReactNode;
  inbox: ReactNode;
  inspector: ReactNode;
};

const navItems = [
  { label: "Inbox", state: "current" as const },
  { label: "My Queue", state: "unavailable" as const },
  { label: "All Runs", state: "unavailable" as const },
  { label: "Entities", state: "unavailable" as const },
  { label: "Reports", state: "unavailable" as const }
];

export function WorkbenchLayout({ detail, inbox, inspector }: Props) {
  return (
    <div className="app-shell">
      <NavRail ariaLabel="Operator sections" brand="OG" items={navItems} />

      <main className="console-frame">
        <header className="topbar">
          <div>
            <p className="product-name">Office Graph</p>
            <h1>Operator Console</h1>
          </div>
          <label className="search-box">
            <span className="sr-only">Search</span>
            <input placeholder="Search items, entities, people, or evidence..." />
          </label>
        </header>

        <div className="workbench">
          <section aria-label="Inbox" className="inbox-pane">
            {inbox}
          </section>

          <section aria-label="Item detail" className="detail-pane">
            {detail}
          </section>

          <aside className="inspector-stack">{inspector}</aside>
        </div>
      </main>
    </div>
  );
}
