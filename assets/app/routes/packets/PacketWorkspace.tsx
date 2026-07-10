import { PacketDetail } from "./components/PacketDetail";
import { PacketList, PacketListFallback } from "./components/PacketList";
import { PacketsLayout } from "./components/PacketsLayout";
import type { PacketRow } from "./types";

type Props = {
  canPageBackward: boolean;
  hasNextPage: boolean;
  loadNextPage: () => void;
  loadPreviousPage: () => void;
  rows: PacketRow[];
  selectedId: string | null;
  selectedPacket: PacketRow | null;
  selectPacket: (id: string) => void;
};

export function PacketWorkspace({
  canPageBackward,
  hasNextPage,
  loadNextPage,
  loadPreviousPage,
  rows,
  selectedId,
  selectedPacket,
  selectPacket
}: Props) {
  return (
    <PacketsLayout
      detail={<PacketDetail packet={selectedPacket} />}
      list={
        <PacketList
          canPageBackward={canPageBackward}
          hasNextPage={hasNextPage}
          onNextPage={loadNextPage}
          onPreviousPage={loadPreviousPage}
          onSelect={selectPacket}
          rows={rows}
          selectedId={selectedId}
        />
      }
    />
  );
}

export function PacketWorkspaceLoading({ isPage }: { isPage: boolean }) {
  return (
    <PacketsLayout
      detail={<PacketDetail packet={null} />}
      list={<PacketListFallback state={isPage ? "page-loading" : "initial-loading"} />}
    />
  );
}

export function PacketWorkspaceError() {
  return (
    <PacketsLayout
      detail={<PacketDetail packet={null} />}
      list={<PacketListFallback state="error" />}
    />
  );
}
