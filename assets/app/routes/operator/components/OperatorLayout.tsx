import type { ReactNode } from "react";
import { WorkspaceShell } from "../../../../src/ui/WorkspaceShell";

type Props = {
  detail: ReactNode;
  inbox: ReactNode;
  inspector: ReactNode;
};

export function OperatorLayout({ detail, inbox, inspector }: Props) {
  return (
    <WorkspaceShell
      brand="OG"
      contentClassName="workbench"
      destinations={[
        { label: "Inbox", to: "/operator" },
        { label: "My Queue" },
        { label: "All Runs" },
        { label: "Entities" },
        { label: "Reports" }
      ]}
      eyebrow="Office Graph"
      headerActions={
        <div className="search-box">
          <input aria-label="Search operator work" disabled placeholder="Search unavailable" />
        </div>
      }
      navigationLabel="Operator sections"
      title="Operator Console"
    >
      {inbox}
      {detail}
      <div className="inspector-stack">{inspector}</div>
    </WorkspaceShell>
  );
}
