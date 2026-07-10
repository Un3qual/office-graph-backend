import type { ReactNode } from "react";
import { WorkspaceShell } from "../../../../src/ui/WorkspaceShell";
import { PRODUCT_DESTINATIONS } from "../../productNavigation";

type Props = {
  detail: ReactNode;
  list: ReactNode;
};

export function PacketsLayout({ detail, list }: Props) {
  return (
    <WorkspaceShell
      brand="OG"
      contentClassName="packet-workspace"
      destinations={PRODUCT_DESTINATIONS}
      eyebrow="Office Graph"
      navigationLabel="Product areas"
      title="Packet Workspace"
    >
      {list}
      {detail}
    </WorkspaceShell>
  );
}
