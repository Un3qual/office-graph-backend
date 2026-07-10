import { Badge } from "../../../../src/ui/Badge";
import { Button } from "../../../../src/ui/Button";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { formatPacketUpdatedAt } from "../formatters";
import type { PacketsWorkflowState } from "../workflow";

type Props = {
  canPageBackward: PacketsWorkflowState["canPageBackward"];
  onNextPage: PacketsWorkflowState["loadNextPage"];
  onPreviousPage: PacketsWorkflowState["loadPreviousPage"];
  onSelect: PacketsWorkflowState["selectPacket"];
  query: PacketsWorkflowState["packetQuery"];
  rows: PacketsWorkflowState["rows"];
  selectedId: PacketsWorkflowState["selectedId"];
};

export function PacketList({
  canPageBackward,
  onNextPage,
  onPreviousPage,
  onSelect,
  query,
  rows,
  selectedId
}: Props) {
  const isInitialLoading = query.isPending || (!query.isSuccess && !query.isError);
  const isPageLoading = query.fetchStatus === "fetching" && !isInitialLoading;
  const hasNextPage = query.data?.hasNextPage ?? false;

  return (
    <section aria-label="Packet queue" className="packet-list-pane">
      <header className="packet-pane-header">
        <div>
          <p className="eyebrow">Read-only queue</p>
          <h2>Packets</h2>
        </div>
        <span>{rows.length} rows</span>
      </header>

      <div className="packet-list-content">
        {isInitialLoading ? (
          <p className="packet-loading" role="status">
            Loading packets...
          </p>
        ) : query.isError ? (
          <div role="alert">
            <EmptyState title="Unable to load packets." tone="error">
              Try again later.
            </EmptyState>
          </div>
        ) : rows.length === 0 ? (
          <EmptyState title="No packets are available.">
            Packets will appear here when work is prepared.
          </EmptyState>
        ) : (
          <div className="packet-list">
            {rows.map((packet) => (
              <button
                aria-current={packet.id === selectedId ? "true" : undefined}
                className="packet-row"
                key={packet.id}
                onClick={() => onSelect(packet.id)}
                type="button"
              >
                <span className="packet-row-title">{packet.title}</span>
                <Badge tone="blue">{formatState(packet.state)}</Badge>
                <span className="packet-row-meta">
                  Updated {formatPacketUpdatedAt(packet.updatedAt)}
                </span>
              </button>
            ))}
          </div>
        )}
      </div>

      <footer aria-label="Packet pagination" className="packet-pagination">
        <span>{rows.length} rows</span>
        <Button isDisabled={!canPageBackward || isPageLoading} onPress={onPreviousPage}>
          Previous
        </Button>
        <Button isDisabled={!hasNextPage || isPageLoading} onPress={onNextPage}>
          Next
        </Button>
      </footer>
      {isPageLoading ? (
        <p className="packet-page-loading" role="status">
          Loading packet page...
        </p>
      ) : null}
    </section>
  );
}

function formatState(value: string) {
  const words = value.replaceAll("_", " ").toLowerCase();

  return words.charAt(0).toUpperCase() + words.slice(1);
}
