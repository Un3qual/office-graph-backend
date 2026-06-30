import type { ReactNode } from "react";

type PanelProps = {
  ariaLabel: string;
  children: ReactNode;
};

export function Panel({ ariaLabel, children }: PanelProps) {
  return (
    <section aria-label={ariaLabel} className="ui-panel">
      {children}
    </section>
  );
}

type PaneHeaderProps = {
  title: string;
  meta?: ReactNode;
};

export function PaneHeader({ title, meta }: PaneHeaderProps) {
  return (
    <div className="ui-pane-header">
      <h2>{title}</h2>
      {meta ? <span>{meta}</span> : null}
    </div>
  );
}

export function PanelRows({ rows }: { rows: Array<[string, string]> }) {
  return (
    <dl className="ui-panel-rows">
      {rows.map(([label, value]) => (
        <div key={label}>
          <dt>{label}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  );
}
