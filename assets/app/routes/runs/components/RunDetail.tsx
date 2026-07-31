import { Link } from "react-router";
import { Badge } from "../../../../src/ui/Badge";
import { Button } from "../../../../src/ui/Button";
import { PanelRows } from "../../../../src/ui/Panel";
import type { RunActivityFragment$key } from "../../../relay/__generated__/RunActivityFragment.graphql";
import type { RunDetailState } from "../types";
import { RunActivity } from "./RunActivity";
import { formatLabel } from "./RunList";

type Props =
  | {
      activityRef: RunActivityFragment$key;
      detail: RunDetailState;
      onRetry: () => void;
      selectedId: string;
      state: "loaded";
    }
  | {
      detail?: null;
      onRetry?: () => void;
      selectedId: string | null;
      state: "empty" | "error" | "loading";
    };

export function RunDetail(props: Props) {
  return (
    <section aria-label="Run detail" className="runs-detail-pane">
      {props.state === "empty" ? <p>Select a run to inspect its current state.</p> : null}
      {props.state === "loading" ? <p role="status">Loading selected run...</p> : null}
      {props.state === "error" ? (
        <div role="alert">
          <p>Selected run details are unavailable.</p>
          {props.onRetry ? <Button onPress={props.onRetry}>Retry run details</Button> : null}
        </div>
      ) : null}
      {props.state === "loaded" ? (
        <LoadedRunDetail
          activityRef={props.activityRef}
          detail={props.detail}
          selectedId={props.selectedId}
        />
      ) : null}
    </section>
  );
}

function LoadedRunDetail({
  activityRef,
  detail,
  selectedId,
}: {
  activityRef: RunActivityFragment$key;
  detail: RunDetailState;
  selectedId: string;
}) {
  const packetVersionRows: Array<[string, string]> = detail.packetVersion
    ? [
        [
          "Packet version",
          `Version ${detail.packetVersion.versionNumber} · ${formatLabel(
            detail.packetVersion.lifecycleState,
          )}`,
        ],
        ["Objective", detail.packetVersion.objective ?? "None"],
      ]
    : [["Packet version", "Not attached"]];

  return (
    <>
      <header className="runs-detail-header">
        <div>
          <p className="eyebrow">Selected run</p>
          <h2>{detail.packet.title}</h2>
        </div>
        <Badge>{formatLabel(detail.status)}</Badge>
      </header>

      <PanelRows
        rows={[
          ["Run", detail.run.id],
          ["Packet", detail.packet.title],
          ...packetVersionRows,
          ["Aggregate", formatLabel(detail.run.aggregateState)],
          ["Execution", formatLabel(detail.run.executionState)],
          ["Verification", formatLabel(detail.run.verificationState)],
        ]}
      />

      <DetailCollection
        emptyText="No required checks."
        items={detail.requiredChecks.map((check) => ({
          id: check.id,
          text: `${check.verificationCheckId ?? "Unknown check"} · ${formatLabel(check.state)}`,
        }))}
        overflowText={
          detail.relationshipOverflow.requiredChecks
            ? "More required checks are available."
            : undefined
        }
        title="Required checks"
      />
      <DetailCollection
        emptyText="No evidence candidates."
        items={detail.evidenceCandidates.map((candidate) => ({
          id: candidate.id,
          text: `${candidate.claim} · ${formatLabel(candidate.state)}`,
        }))}
        overflowText={
          detail.relationshipOverflow.evidenceCandidates
            ? "More evidence candidates are available."
            : undefined
        }
        title="Evidence candidates"
      />
      <DetailCollection
        emptyText="No accepted evidence."
        items={detail.evidenceItems.map((item) => ({
          id: item.id,
          text: `${item.id} · ${formatLabel(item.state)}`,
        }))}
        overflowText={
          detail.relationshipOverflow.evidenceItems
            ? "More evidence items are available."
            : undefined
        }
        title="Evidence"
      />
      <DetailCollection
        emptyText="No missing evidence."
        items={detail.missingEvidence.map((missing) => ({
          id: `${missing.verificationCheckId}:${missing.reason}`,
          text: `${missing.verificationCheckId} · ${formatLabel(missing.reason)}`,
        }))}
        title="Missing evidence"
      />
      <DetailCollection
        emptyText="No verification results."
        items={detail.verificationResults.map((result) => ({
          id: result.id,
          text: `${result.verificationCheckId} · ${formatLabel(
            result.result,
          )} · ${formatLabel(result.policyBasis)}`,
        }))}
        overflowText={
          detail.relationshipOverflow.verificationResults
            ? "More verification results are available."
            : undefined
        }
        title="Verification results"
      />

      <RunActivity activityRef={activityRef} key={selectedId} />

      <div className="runs-detail-actions">
        <Link
          className="ui-button ui-button-secondary"
          to={`/packets?packetId=${encodeURIComponent(detail.packet.relayId)}`}
        >
          Open packet history
        </Link>
        <Link
          className="ui-button ui-button-primary"
          to={`/operator?runId=${encodeURIComponent(selectedId)}`}
        >
          Open run in Operator
        </Link>
      </div>
    </>
  );
}

function DetailCollection({
  emptyText,
  items,
  overflowText,
  title,
}: {
  emptyText: string;
  items: Array<{ id: string; text: string }>;
  overflowText?: string;
  title: string;
}) {
  return (
    <section className="runs-detail-section">
      <h3>{title}</h3>
      {items.length === 0 ? (
        <p>{emptyText}</p>
      ) : (
        <ul>
          {items.map((item) => (
            <li key={item.id}>{item.text}</li>
          ))}
        </ul>
      )}
      {overflowText ? <p>{overflowText}</p> : null}
    </section>
  );
}
