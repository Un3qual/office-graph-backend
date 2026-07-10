import { PacketDetail } from "./components/PacketDetail";
import { PacketList } from "./components/PacketList";
import { PacketsLayout } from "./components/PacketsLayout";
import type { PacketsWorkflowState } from "./workflow";

type Props = {
  workflow: PacketsWorkflowState;
};

export function PacketWorkspace({ workflow }: Props) {
  return (
    <PacketsLayout
      detail={<PacketDetail packet={workflow.selectedPacket} />}
      list={
        <PacketList
          canPageBackward={workflow.canPageBackward}
          onNextPage={workflow.loadNextPage}
          onPreviousPage={workflow.loadPreviousPage}
          onSelect={workflow.selectPacket}
          query={workflow.packetQuery}
          rows={workflow.rows}
          selectedId={workflow.selectedId}
        />
      }
    />
  );
}
