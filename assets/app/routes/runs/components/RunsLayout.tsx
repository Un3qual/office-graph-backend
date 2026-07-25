import type { ReactNode } from "react";
import { WorkspaceShell } from "../../../../src/ui/WorkspaceShell";
import { PRODUCT_DESTINATIONS } from "../../productNavigation";

type Props = {
  detail: ReactNode;
  list: ReactNode;
};

export function RunsLayout({ detail, list }: Props) {
  return (
    <WorkspaceShell
      brand="OG"
      contentClassName="runs-workspace"
      destinations={PRODUCT_DESTINATIONS}
      eyebrow="Office Graph"
      navigationLabel="Product areas"
      title="All Runs"
    >
      {list}
      {detail}
    </WorkspaceShell>
  );
}
