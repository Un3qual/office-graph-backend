import { Badge } from "../../../../src/ui/Badge";
import { Button } from "../../../../src/ui/Button";
import { EmptyState } from "../../../../src/ui/EmptyState";
import { formatPacketState, formatPacketUpdatedAt } from "../formatters";
import type { PacketRow } from "../types";

type Props = {
  canPageBackward: boolean;
  hasNextPage: boolean;
  onNextPage: () => void;
  onPreviousPage: () => void;
  onSelect: (id: string) => void;
  rows: PacketRow[];
  selectedId: string | null;
};

type FallbackProps = {
  canPageBackward?: boolean;
  onPreviousPage?: () => void;
  state: "error" | "initial-loading" | "page-loading";
};

export function PacketList({
  canPageBackward,
  hasNextPage,
  onNextPage,
  onPreviousPage,
  onSelect,
  rows,
  selectedId,
}: Props) {
  return (
    <PacketListFrame
      footer={
        <>
          <Button isDisabled={!canPageBackward} onPress={onPreviousPage}>
            Previous
          </Button>
          <Button isDisabled={!hasNextPage} onPress={onNextPage}>
            Next
          </Button>
        </>
      }
      rowCount={rows.length}
    >
      {rows.length === 0 ? (
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
              <Badge tone="blue">{formatPacketState(packet.state)}</Badge>
              <span className="packet-row-meta">
                Updated {formatPacketUpdatedAt(packet.updatedAt)}
              </span>
            </button>
          ))}
        </div>
      )}
    </PacketListFrame>
  );
}

export function PacketListFallback({
  canPageBackward = false,
  onPreviousPage,
  state,
}: FallbackProps) {
  const loadingMessage = state === "page-loading" ? "Loading packet page..." : "Loading packets...";

  return (
    <PacketListFrame
      footer={
        <>
          <Button isDisabled={!canPageBackward} onPress={onPreviousPage}>
            Previous
          </Button>
          <Button isDisabled>Next</Button>
        </>
      }
      rowCount={0}
    >
      {state === "error" ? (
        <div role="alert">
          <EmptyState title="Unable to load packets." tone="error">
            Try again later.
          </EmptyState>
        </div>
      ) : (
        <p
          className={state === "page-loading" ? "packet-page-loading" : "packet-loading"}
          role="status"
        >
          {loadingMessage}
        </p>
      )}
    </PacketListFrame>
  );
}

function PacketListFrame({
  children,
  footer,
  rowCount,
}: {
  children: React.ReactNode;
  footer: React.ReactNode;
  rowCount: number;
}) {
  return (
    <section aria-label="Packet queue" className="packet-list-pane">
      <header className="packet-pane-header">
        <div>
          <p className="eyebrow">Work packet workspace</p>
          <h2>Packets</h2>
        </div>
        <span>{rowCount} rows</span>
      </header>
      <div className="packet-list-content">{children}</div>
      <footer aria-label="Packet pagination" className="packet-pagination">
        <span>{rowCount} rows</span>
        {footer}
      </footer>
    </section>
  );
}
