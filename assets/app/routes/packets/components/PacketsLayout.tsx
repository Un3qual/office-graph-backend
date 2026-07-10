import type { ReactNode } from "react";
import { WorkspaceShell } from "../../../../src/ui/WorkspaceShell";

type Props = {
  detail: ReactNode;
  list: ReactNode;
};

export function PacketsLayout({ detail, list }: Props) {
  return (
    <WorkspaceShell
      brand="OG"
      contentClassName="packet-workspace"
      destinations={[
        { label: "Operator", to: "/operator" },
        { label: "Packets", to: "/packets" },
        { label: "All Runs" },
        { label: "Entities" },
        { label: "Reports" }
      ]}
      eyebrow="Office Graph"
      navigationLabel="Product areas"
      title="Packet Workspace"
    >
      {list}
      {detail}
    </WorkspaceShell>
  );
}
