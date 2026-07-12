import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { Button } from "../../../src/ui/Button";
import { useState } from "react";
import { PacketDetail } from "./components/PacketDetail";
import { PacketCreateForm } from "./components/PacketCreateForm";
import { PacketList, PacketListFallback } from "./components/PacketList";
import { PacketsLayout } from "./components/PacketsLayout";
import type { PacketRow, PacketsPage } from "./types";
import { usePacketWorkspaceDetail } from "./workflow";

type Props = {
  canPageBackward: boolean;
  canCreatePacket: boolean;
  fetchKey: number;
  hasNextPage: boolean;
  loadNextPage: () => void;
  loadPreviousPage: () => void;
  onRefresh: () => void;
  rows: PacketRow[];
  selectedId: string | null;
  selectedPacket: PacketRow | null;
  selectCreatedPacket: (operationId: string) => void;
  selectPacket: (id: string) => void;
};

export function PacketWorkspace({
  canPageBackward,
  canCreatePacket,
  fetchKey,
  hasNextPage,
  loadNextPage,
  loadPreviousPage,
  onRefresh,
  rows,
  selectedId,
  selectedPacket,
  selectCreatedPacket,
  selectPacket
}: Props) {
  return (
    <PacketsLayout
      detail={
        <div className="packet-detail-column">
          {canCreatePacket ? (
            <PacketCreateForm onCreated={selectCreatedPacket} onRefresh={onRefresh} />
          ) : null}
          {selectedPacket ? (
            <AsyncBoundary
              errorFallback={
                <div>
                  <PacketDetail packet={selectedPacket} />
                  <p className="packet-detail-error" role="alert">Unable to load packet contract details.</p>
                  <Button onPress={onRefresh}>Retry packet details</Button>
                </div>
              }
              loadingFallback={
                <div>
                  <PacketDetail packet={selectedPacket} />
                  <p className="packet-detail-loading" role="status">Loading packet contract...</p>
                </div>
              }
              resetKey={`packet-detail:${selectedPacket.id}:${fetchKey}`}
            >
              <LoadedPacketDetail
                fetchKey={fetchKey}
                key={selectedPacket.id}
                onRefresh={onRefresh}
                packet={selectedPacket}
              />
            </AsyncBoundary>
          ) : (
            <PacketDetail packet={null} />
          )}
        </div>
      }
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

function LoadedPacketDetail({
  fetchKey,
  onRefresh,
  packet
}: {
  fetchKey: number;
  onRefresh: () => void;
  packet: PacketRow;
}) {
  const [versionPage, setVersionPage] = useState<PacketsPage>({ first: 2, after: null });
  const [previousCursors, setPreviousCursors] = useState<Array<string | null>>([]);
  const workspace = usePacketWorkspaceDetail(packet.id, versionPage, fetchKey);
  const nextCursor = workspace.versionPageInfo.endCursor ?? null;

  const loadNextVersions = () => {
    if (!workspace.versionPageInfo.hasNextPage || !nextCursor) return;
    setPreviousCursors((cursors) => [...cursors, versionPage.after]);
    setVersionPage((page) => ({ ...page, after: nextCursor }));
  };

  const loadPreviousVersions = () => {
    const previous = previousCursors.at(-1);
    if (previous === undefined) return;
    setPreviousCursors((cursors) => cursors.slice(0, -1));
    setVersionPage((page) => ({ ...page, after: previous }));
  };

  return (
    <PacketDetail
      key={`${workspace.packet.id}:${workspace.currentVersion.id}`}
      onNextVersions={loadNextVersions}
      onPreviousVersions={loadPreviousVersions}
      onRefresh={onRefresh}
      packet={packet}
      workspace={workspace}
    />
  );
}

export function PacketWorkspaceLoading({ isPage }: { isPage: boolean }) {
  return (
    <PacketsLayout
      detail={<div className="packet-detail-column"><PacketDetail packet={null} /></div>}
      list={<PacketListFallback state={isPage ? "page-loading" : "initial-loading"} />}
    />
  );
}

export function PacketWorkspaceError({
  canPageBackward,
  onRetry,
  onPreviousPage
}: {
  canPageBackward: boolean;
  onRetry: () => void;
  onPreviousPage: () => void;
}) {
  return (
    <PacketsLayout
      detail={<div className="packet-detail-column"><PacketDetail packet={null} /></div>}
      list={
        <>
          <PacketListFallback
            canPageBackward={canPageBackward}
            onPreviousPage={onPreviousPage}
            state="error"
          />
          <Button onPress={onRetry}>Retry packets</Button>
        </>
      }
    />
  );
}
