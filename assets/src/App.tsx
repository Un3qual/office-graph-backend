import "./styles/global.css";

const navItems = ["Inbox", "My Queue", "All Runs", "Entities", "Reports"];

export function App() {
  return (
    <div className="app-shell">
      <aside className="icon-rail">
        <div className="brand-mark" aria-hidden="true">
          OG
        </div>
        <nav aria-label="Operator sections">
          {navItems.map((item) => (
            <button className={item === "Inbox" ? "rail-item rail-item-active" : "rail-item"} key={item}>
              <span aria-hidden="true">{item.slice(0, 1)}</span>
              <span>{item}</span>
            </button>
          ))}
        </nav>
      </aside>

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
            <div className="pane-header">
              <h2>Inbox</h2>
              <span>0 items</span>
            </div>
            <div className="empty-state">No operator workflow items.</div>
          </section>

          <section aria-label="Item detail" className="detail-pane">
            <div className="detail-header">
              <p className="eyebrow">Selected item</p>
              <h2>No item selected</h2>
            </div>
            <div className="stepper" aria-label="Workflow steps">
              {["Manual Intake", "Packet Readiness", "Run State", "Evidence", "Verification"].map(
                (step) => (
                  <span key={step}>{step}</span>
                )
              )}
            </div>
          </section>

          <aside className="inspector-stack">
            <section aria-label="Packet Readiness" className="inspector-panel">
              <h2>Packet Readiness</h2>
              <p>No packet selected.</p>
            </section>
            <section aria-label="Run State" className="inspector-panel">
              <h2>Run State</h2>
              <p>No run selected.</p>
            </section>
            <section aria-label="Verification" className="inspector-panel">
              <h2>Verification</h2>
              <p>No verification outcome selected.</p>
            </section>
          </aside>
        </div>
      </main>
    </div>
  );
}
