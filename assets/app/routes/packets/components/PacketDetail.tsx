import { Badge } from "../../../../src/ui/Badge";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { formatPacketState, formatPacketUpdatedAt } from "../formatters";
import type { PacketRow } from "../types";

type Props = {
  packet: PacketRow | null;
};

export function PacketDetail({ packet }: Props) {
  return (
    <section aria-label="Packet detail" className="packet-detail-pane">
      {packet ? (
        <>
          <header className="packet-detail-header">
            <div>
              <p className="eyebrow">Selected packet</p>
              <h2>{packet.title}</h2>
            </div>
            <Badge tone="blue">{formatPacketState(packet.state)}</Badge>
          </header>
          <dl className="packet-detail-list">
            <div>
              <dt>Lifecycle state</dt>
              <dd>{formatPacketState(packet.state)}</dd>
            </div>
            <div>
              <dt>Updated</dt>
              <dd>
                <time dateTime={packet.updatedAt}>
                  {formatPacketUpdatedAt(packet.updatedAt)}
                </time>
              </dd>
            </div>
            <div>
              <dt>Current version</dt>
              <dd className="packet-compatibility-id">{packet.currentVersionId ?? "Not linked"}</dd>
            </div>
            <div>
              <dt>Operation</dt>
              <dd className="packet-compatibility-id">{packet.operationId ?? "Not linked"}</dd>
            </div>
          </dl>
        </>
      ) : (
        <EmptyState title="No packet selected.">
          Select a packet to inspect its current summary.
        </EmptyState>
      )}
    </section>
  );
}
