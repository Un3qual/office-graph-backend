import type { ReactNode } from "react";
import { WorkspaceShell } from "../../../../src/ui/WorkspaceShell";
import { PRODUCT_DESTINATIONS } from "../../productNavigation";

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
      destinations={PRODUCT_DESTINATIONS}
      eyebrow="Office Graph"
      headerActions={
        <div className="search-box">
          <input aria-label="Search operator work" disabled placeholder="Search unavailable" />
        </div>
      }
      navigationLabel="Product areas"
      title="Operator Console"
    >
      {inbox}
      {detail}
      <div className="inspector-stack">{inspector}</div>
    </WorkspaceShell>
  );
}
