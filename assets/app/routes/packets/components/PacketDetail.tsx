import { Badge } from "../../../../src/ui/Badge";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { formatPacketState, formatPacketUpdatedAt } from "../formatters";
import type { PacketRow } from "../types";
import type { PacketWorkspaceDetail } from "../types";
import { PacketEditor } from "./PacketEditor";
import { PacketRunForm } from "./PacketRunForm";

type Props = {
  onRefresh?: () => void;
  packet: PacketRow | null;
  workspace?: PacketWorkspaceDetail | null;
};

export function PacketDetail({ onRefresh, packet, workspace = null }: Props) {
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
          {workspace ? (
            <div className="packet-version-workspace">
              <section aria-label="Current packet version" className="packet-contract-summary">
                <p className="eyebrow">Execution contract</p>
                <h3>Current version {workspace.currentVersion.versionNumber}</h3>
                <dl className="packet-contract-detail-list">
                  <div><dt>Objective</dt><dd>{workspace.currentVersion.objective}</dd></div>
                  <div><dt>Context</dt><dd>{workspace.currentVersion.contextSummary}</dd></div>
                  <div><dt>Requirements</dt><dd>{workspace.currentVersion.requirements}</dd></div>
                  <div><dt>Success criteria</dt><dd>{workspace.currentVersion.successCriteria}</dd></div>
                </dl>
              </section>
              <section aria-label="Version history" className="packet-version-history">
                <p className="eyebrow">Immutable history</p>
                <h3>Versions</h3>
                <ol>
                  {workspace.versions.map(version => (
                    <li data-current={version.id === workspace.currentVersion.id} key={version.id}>
                      <strong>Version {version.versionNumber}</strong>
                      <span>{version.title}</span>
                      <span>{version.lifecycleState}</span>
                    </li>
                  ))}
                </ol>
              </section>
              {onRefresh ? <PacketEditor onRefresh={onRefresh} workspace={workspace} /> : null}
              {onRefresh ? <PacketRunForm onRefresh={onRefresh} workspace={workspace} /> : null}
            </div>
          ) : null}
        </>
      ) : (
        <EmptyState title="No packet selected.">
          Select a packet to inspect its current summary.
        </EmptyState>
      )}
    </section>
  );
}
