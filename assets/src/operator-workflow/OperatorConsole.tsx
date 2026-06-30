import { useEffect, useMemo, useState } from "react";
import { StatusBadge } from "../components/StatusBadge";
import {
  createOperatorWorkflowApi,
  type OperatorEvidenceCandidate,
  type OperatorInbox,
  type OperatorObservation,
  type OperatorRunState,
  type OperatorVerificationResult,
  type OperatorWorkflowApi,
  type OperatorWorkflowItem,
  type PacketReadiness,
  type PacketReadinessInput,
  type VerificationOutcome
} from "./api";
import { listSummary, shortId } from "./presentation";
import { actionLabel, formatWorkflowStatus } from "./status";

type Loadable<T> =
  | { state: "idle" | "loading" }
  | { state: "loaded"; data: T }
  | { state: "error"; message: string };

type Props = {
  api?: OperatorWorkflowApi;
};

const defaultApi = createOperatorWorkflowApi();
const navItems = ["Inbox", "My Queue", "All Runs", "Entities", "Reports"];

export function OperatorConsole({ api = defaultApi }: Props) {
  const [inbox, setInbox] = useState<Loadable<OperatorInbox>>({ state: "loading" });
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [item, setItem] = useState<Loadable<OperatorWorkflowItem>>({ state: "idle" });
  const [readiness, setReadiness] = useState<Loadable<PacketReadiness>>({ state: "idle" });
  const [runState, setRunState] = useState<Loadable<OperatorRunState>>({ state: "idle" });
  const [verification, setVerification] = useState<Loadable<VerificationOutcome>>({
    state: "idle"
  });

  useEffect(() => {
    let cancelled = false;

    setInbox({ state: "loading" });
    api
      .loadInbox()
      .then((nextInbox) => {
        if (cancelled) {
          return;
        }

        setInbox({ state: "loaded", data: nextInbox });
        setSelectedId(nextInbox.rows[0]?.normalized_event_id ?? null);
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setInbox({ state: "error", message: errorMessage(error) });
        }
      });

    return () => {
      cancelled = true;
    };
  }, [api]);

  useEffect(() => {
    if (!selectedId) {
      setItem({ state: "idle" });
      setReadiness({ state: "idle" });
      setRunState({ state: "idle" });
      setVerification({ state: "idle" });
      return;
    }

    let cancelled = false;

    setItem({ state: "loading" });
    setReadiness({ state: "idle" });
    setRunState({ state: "idle" });
    setVerification({ state: "idle" });

    api
      .loadItem(selectedId)
      .then((nextItem) => {
        if (cancelled) {
          return;
        }

        setItem({ state: "loaded", data: nextItem });
        loadReadiness(api, nextItem, setReadiness, () => cancelled);
        loadRun(api, nextItem, setRunState, setVerification, () => cancelled);
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setItem({ state: "error", message: errorMessage(error) });
        }
      });

    return () => {
      cancelled = true;
    };
  }, [api, selectedId]);

  const rows = inbox.state === "loaded" ? inbox.data.rows : [];
  const selectedItem = item.state === "loaded" ? item.data : null;

  return (
    <div className="app-shell">
      <aside className="icon-rail">
        <div className="brand-mark" aria-hidden="true">
          OG
        </div>
        <nav aria-label="Operator sections">
          {navItems.map((navItem) => (
            <button
              className={navItem === "Inbox" ? "rail-item rail-item-active" : "rail-item"}
              key={navItem}
            >
              <span aria-hidden="true">{navItem.slice(0, 1)}</span>
              <span>{navItem}</span>
            </button>
          ))}
        </nav>
      </aside>

      <main className="console-frame">
        <header className="topbar">
          <div>
            <p className="product-name">Office Graph</p>
            <h1>Operator Console</h1>
          </div>
          <label className="search-box">
            <span className="sr-only">Search</span>
            <input placeholder="Search items, entities, people, or evidence..." />
          </label>
        </header>

        <div className="workbench">
          <section aria-label="Inbox" className="inbox-pane">
            <InboxContent
              inbox={inbox}
              rows={rows}
              selectedId={selectedId}
              onSelect={setSelectedId}
            />
          </section>

          <section aria-label="Item detail" className="detail-pane">
            <DetailContent item={item} selectedItem={selectedItem} />
          </section>

          <aside className="inspector-stack">
            <ReadinessPanel readiness={readiness} selectedItem={selectedItem} />
            <RunStatePanel runState={runState} />
            <VerificationPanel verification={verification} />
          </aside>
        </div>
      </main>
    </div>
  );
}

function InboxContent({
  inbox,
  rows,
  selectedId,
  onSelect
}: {
  inbox: Loadable<OperatorInbox>;
  rows: OperatorWorkflowItem[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}) {
  const countLabel = inbox.state === "loaded" ? `${inbox.data.rows.length} items` : "";

  return (
    <>
      <div className="pane-header">
        <h2>Inbox</h2>
        <span>{countLabel}</span>
      </div>
      {inbox.state === "loading" ? <div className="empty-state">Loading inbox...</div> : null}
      {inbox.state === "error" ? <div className="empty-state error-state">{inbox.message}</div> : null}
      {inbox.state === "loaded" && inbox.data.empty ? (
        <div className="empty-state">No operator workflow items.</div>
      ) : null}
      {rows.length > 0 ? (
        <div className="inbox-list">
          {rows.map((row) => (
            <button
              aria-current={row.normalized_event_id === selectedId ? "true" : undefined}
              className="inbox-row"
              key={row.normalized_event_id}
              onClick={() => onSelect(row.normalized_event_id)}
            >
              <span className="row-title" title={row.normalized_event_id}>
                {shortId(row.normalized_event_id)}
              </span>
              <span className="row-source">{row.source.identity}</span>
              <StatusBadge status={row.status} />
              <span className="row-meta">
                {row.blocker_reasons.length > 0
                  ? `Blockers ${row.blocker_reasons.join(", ")}`
                  : `Actions ${row.allowed_next_actions.map(actionLabel).join(", ") || "None"}`}
              </span>
              <span className="row-meta" title={row.source_watermark ?? "none"}>
                Watermark {shortId(row.source_watermark)}
              </span>
            </button>
          ))}
        </div>
      ) : null}
    </>
  );
}

function DetailContent({
  item,
  selectedItem
}: {
  item: Loadable<OperatorWorkflowItem>;
  selectedItem: OperatorWorkflowItem | null;
}) {
  if (item.state === "loading") {
    return <div className="empty-state">Loading item detail...</div>;
  }

  if (item.state === "error") {
    return <div className="empty-state error-state">{item.message}</div>;
  }

  if (!selectedItem) {
    return (
      <div className="detail-header">
        <p className="eyebrow">Selected item</p>
        <h2>No item selected</h2>
      </div>
    );
  }

  return (
    <>
      <div className="detail-header">
        <p className="eyebrow">Selected item</p>
        <h2>{selectedItem.normalized_event_id}</h2>
        <StatusBadge status={selectedItem.status} />
      </div>
      <div className="stepper" aria-label="Workflow steps">
        {["Manual Intake", "Packet Readiness", "Run State", "Evidence", "Verification"].map(
          (step) => (
            <span key={step}>{step}</span>
          )
        )}
      </div>
      <dl className="detail-list">
        <div>
          <dt>Typed identity</dt>
          <dd>
            {selectedItem.typed_id.type}: {selectedItem.typed_id.id}
          </dd>
        </div>
        <div>
          <dt>Source</dt>
          <dd>{selectedItem.source.identity}</dd>
        </div>
        <div>
          <dt>Outcome</dt>
          <dd>{formatWorkflowStatus(selectedItem.source.outcome)}</dd>
        </div>
        <div>
          <dt>Allowed next actions</dt>
          <dd>{selectedItem.allowed_next_actions.map(actionLabel).join(", ") || "None"}</dd>
        </div>
        <div>
          <dt>Proposed changes</dt>
          <dd>
            {selectedItem.proposed_change_status.applied} applied /{" "}
            {selectedItem.proposed_change_status.pending} pending
          </dd>
        </div>
        <div>
          <dt>Graph links</dt>
          <dd title={selectedItem.graph_links.map((link) => link.title).join(", ")}>
            {listSummary(
              selectedItem.graph_links.map((link) => link.title),
              2
            )}
          </dd>
        </div>
        <div>
          <dt>Audit trace</dt>
          <dd>{selectedItem.audit_trace.resource_count} resources</dd>
        </div>
        <div>
          <dt>Revision trace</dt>
          <dd>{selectedItem.revision_trace.resource_count} resources</dd>
        </div>
      </dl>
    </>
  );
}

function ReadinessPanel({
  readiness,
  selectedItem
}: {
  readiness: Loadable<PacketReadiness>;
  selectedItem: OperatorWorkflowItem | null;
}) {
  const input = selectedItem ? packetReadinessInput(selectedItem) : null;

  return (
    <section aria-label="Packet Readiness" className="inspector-panel">
      <h2>Packet Readiness</h2>
      {readiness.state === "loading" ? <p>Loading readiness...</p> : null}
      {readiness.state === "idle" ? <p>No packet selected.</p> : null}
      {readiness.state === "error" ? <p className="error-text">{readiness.message}</p> : null}
      {readiness.state === "loaded" ? (
        <PanelRows
          rows={[
            ["Status", formatWorkflowStatus(readiness.data.status)],
            ["Objective", packetInputText(input?.objective)],
            ["Context", packetInputText(input?.context_summary)],
            ["Success criteria", packetInputText(input?.success_criteria)],
            ["Autonomy", packetInputStatus(input?.autonomy_posture)],
            [
              "Source references",
              listSummary(
                readiness.data.source_links.map((link) => link.title),
                2
              )
            ],
            ["Required", String(readiness.data.required_checks.length)],
            ["Blockers", readiness.data.blocker_reasons.join(", ") || "None"],
            ["Actions", readiness.data.allowed_next_actions.map(actionLabel).join(", ") || "None"]
          ]}
        />
      ) : null}
    </section>
  );
}

function RunStatePanel({ runState }: { runState: Loadable<OperatorRunState> }) {
  return (
    <section aria-label="Run State" className="inspector-panel">
      <h2>Run State</h2>
      {runState.state === "loading" ? <p>Loading run state...</p> : null}
      {runState.state === "idle" ? <p>No run linked yet.</p> : null}
      {runState.state === "error" ? <p className="error-text">{runState.message}</p> : null}
      {runState.state === "loaded" ? (
        <PanelRows
          rows={[
            ["Status", formatWorkflowStatus(runState.data.status)],
            ["Run ID", runState.data.run.id],
            ["Execution", formatWorkflowStatus(runState.data.run.execution_state)],
            ["Required checks", String(runState.data.required_checks.length)],
            ["Actions", runState.data.allowed_next_actions.map(actionLabel).join(", ") || "None"],
            ["Observations", formatObservationDetails(runState.data.observations)],
            ["Evidence candidates", formatEvidenceCandidateDetails(runState.data.evidence_candidates)],
            ["Verification results", String(runState.data.verification_results.length)],
            [
              "Missing evidence",
              runState.data.missing_evidence
                .map((item) => String(item.reason ?? "missing"))
                .join(", ") || "None"
            ]
          ]}
        />
      ) : null}
    </section>
  );
}

function VerificationPanel({ verification }: { verification: Loadable<VerificationOutcome> }) {
  return (
    <section aria-label="Verification" className="inspector-panel">
      <h2>Verification</h2>
      {verification.state === "loading" ? <p>Loading verification...</p> : null}
      {verification.state === "idle" ? <p>No verification outcome selected.</p> : null}
      {verification.state === "error" ? <p className="error-text">{verification.message}</p> : null}
      {verification.state === "loaded" ? (
        <PanelRows
          rows={[
            ["Status", formatWorkflowStatus(verification.data.status)],
            ["Run ID", verification.data.run.id],
            ["Accepted evidence", String(verification.data.verification_results.length)],
            ["Results", formatVerificationResultDetails(verification.data.verification_results)],
            [
              "Missing evidence",
              verification.data.missing_evidence
                .map((item) => String(item.reason ?? "missing"))
                .join(", ") || "None"
            ]
          ]}
        />
      ) : null}
    </section>
  );
}

function PanelRows({ rows }: { rows: Array<[string, string]> }) {
  return (
    <dl className="panel-rows">
      {rows.map(([label, value]) => (
        <div key={label}>
          <dt>{label}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  );
}

function loadReadiness(
  api: OperatorWorkflowApi,
  item: OperatorWorkflowItem,
  setReadiness: (state: Loadable<PacketReadiness>) => void,
  isCancelled: () => boolean
) {
  const input = packetReadinessInput(item);

  setReadiness({ state: "loading" });
  api
    .loadPacketReadiness(input)
    .then((data) => {
      if (!isCancelled()) {
        setReadiness({ state: "loaded", data });
      }
    })
    .catch((error: unknown) => {
      if (!isCancelled()) {
        setReadiness({ state: "error", message: errorMessage(error) });
      }
    });
}

function loadRun(
  api: OperatorWorkflowApi,
  item: OperatorWorkflowItem,
  setRunState: (state: Loadable<OperatorRunState>) => void,
  setVerification: (state: Loadable<VerificationOutcome>) => void,
  isCancelled: () => boolean
) {
  const runLink = item.graph_links.find((link) => link.type === "work_run");

  if (!runLink) {
    return;
  }

  setRunState({ state: "loading" });
  setVerification({ state: "loading" });

  api
    .loadRunState(runLink.id)
    .then((data) => {
      if (!isCancelled()) {
        setRunState({ state: "loaded", data });
      }
    })
    .catch((error: unknown) => {
      if (!isCancelled()) {
        setRunState({ state: "error", message: errorMessage(error) });
      }
    });

  api
    .loadVerificationOutcome(runLink.id)
    .then((data) => {
      if (!isCancelled()) {
        setVerification({ state: "loaded", data });
      }
    })
    .catch((error: unknown) => {
      if (!isCancelled()) {
        setVerification({ state: "error", message: errorMessage(error) });
      }
    });
}

function packetReadinessInput(item: OperatorWorkflowItem): PacketReadinessInput {
  const sourceLinks = item.graph_links.filter(
    (link) => link.graph_item_id && link.type !== "work_run"
  );
  const verificationChecks = item.graph_links.filter((link) => link.type === "verification_check");

  return {
    source_graph_item_ids: sourceLinks.flatMap((link) =>
      link.graph_item_id ? [link.graph_item_id] : []
    ),
    verification_check_ids: verificationChecks.map((link) => link.id)
  };
}

function packetInputText(value: string | undefined) {
  return value && value.trim() !== "" ? value : "None";
}

function packetInputStatus(value: string | undefined) {
  return value && value.trim() !== "" ? formatWorkflowStatus(value) : "None";
}

function formatObservationDetails(observations: OperatorObservation[]) {
  return listSummary(
    observations.map((observation) =>
      [
        observation.id,
        formatWorkflowStatus(observation.normalized_status),
        formatWorkflowStatus(observation.freshness_state),
        formatWorkflowStatus(observation.trust_basis),
        observation.source_identity
      ].join(" / ")
    ),
    2
  );
}

function formatEvidenceCandidateDetails(candidates: OperatorEvidenceCandidate[]) {
  return listSummary(
    candidates.map((candidate) => {
      const observationId = candidate.execution_observation_id ?? "no observation";

      return [
        candidate.id,
        formatWorkflowStatus(candidate.state),
        formatWorkflowStatus(candidate.freshness_state),
        formatWorkflowStatus(candidate.trust_basis),
        candidate.source_identity,
        candidate.claim,
        `Observation ${observationId}`
      ].join(" / ");
    }),
    2
  );
}

function formatVerificationResultDetails(results: OperatorVerificationResult[]) {
  return listSummary(
    results.map((result) =>
      [
        result.id,
        formatWorkflowStatus(result.result),
        `Evidence ${result.evidence_item_id ?? "none"}`,
        `Policy ${formatWorkflowStatus(result.policy_basis ?? "none")}`,
        `Operation ${result.operation_id ?? "none"}`,
        `Actor ${result.actor_principal_id ?? "none"}`,
        `Target ${result.target_graph_item_id ?? "none"}`
      ].join(" / ")
    ),
    2
  );
}

function errorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return "The operator workflow request failed.";
}
