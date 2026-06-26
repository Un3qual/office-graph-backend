type Fetcher = (input: string, init: RequestInit) => Promise<Response>;

type Trace = {
  operation_id: string | null;
  resource_count: number;
  resources: Array<{ type: string; id: string }>;
};

export type OperatorWorkflowItem = {
  type: "operator_workflow_item";
  typed_id: { type: string; id: string };
  normalized_event_id: string;
  duplicate_of_id: string | null;
  status: string;
  reason_codes: string[];
  source: {
    identity: string;
    replay_identity: string;
    outcome: string;
  };
  proposed_change_status: {
    pending: number;
    applied: number;
    rejected: number;
    total: number;
  };
  blocker_reasons: string[];
  allowed_next_actions: string[];
  operation_watermark: string | null;
  source_watermark: string | null;
  graph_links: Array<{
    type: string;
    id: string;
    graph_item_id: string;
    title: string;
    state: string | null;
  }>;
  graph_relationships: Array<{
    id: string;
    source_graph_item_id: string;
    target_graph_item_id: string;
    relationship_type: string;
  }>;
  audit_trace: Trace;
  revision_trace: Trace;
};

export type OperatorInbox = {
  type: "operator_inbox";
  empty: boolean;
  source_watermark: string | null;
  rows: OperatorWorkflowItem[];
};

export type PacketReadinessInput = {
  title: string;
  objective: string;
  context_summary: string;
  requirements: string;
  success_criteria: string;
  autonomy_posture: string;
  source_graph_item_ids: string[];
  verification_check_ids: string[];
};

export type PacketReadiness = {
  type: "packet_readiness";
  ready: boolean;
  status: string;
  allowed_next_actions: string[];
  blocker_reasons: string[];
  source_links: Array<{ type: string; id: string; graph_item_id: string; title: string }>;
  required_checks: Array<{ id: string; graph_item_id: string; state: string }>;
  source_watermark: string | null;
};

export type OperatorRunState = {
  type: "operator_run_state";
  status: string;
  allowed_next_actions: string[];
  source_watermark: string | null;
  packet: { id: string; title: string; state: string };
  packet_version: {
    id: string;
    version_number: number;
    lifecycle_state: string;
    objective: string;
  };
  run: {
    id: string;
    aggregate_state: string;
    execution_state: string;
    verification_state: string;
  };
  required_checks: Array<Record<string, unknown>>;
  observations: Array<Record<string, unknown>>;
  evidence_candidates: Array<Record<string, unknown>>;
  evidence_items: Array<Record<string, unknown>>;
  verification_results: Array<Record<string, unknown>>;
  missing_evidence: Array<Record<string, unknown>>;
};

export type VerificationOutcome = {
  type: "verification_outcome";
  status: string;
  source_watermark: string | null;
  run: OperatorRunState["run"];
  verification_results: OperatorRunState["verification_results"];
  missing_evidence: OperatorRunState["missing_evidence"];
};

export class OperatorWorkflowApiError extends Error {
  code: string;
  detail: string;
  status: number;
  payload: unknown;

  constructor(status: number, payload: unknown) {
    const envelope = parseErrorEnvelope(payload);
    super(envelope.detail);
    this.name = "OperatorWorkflowApiError";
    this.code = envelope.code;
    this.detail = envelope.detail;
    this.status = status;
    this.payload = payload;
  }
}

export function createOperatorWorkflowApi({ fetcher = fetch }: { fetcher?: Fetcher } = {}) {
  return {
    loadInbox: () => request<OperatorInbox>(fetcher, "/api/operator-workflow/inbox"),
    loadItem: (normalizedEventId: string) =>
      request<OperatorWorkflowItem>(
        fetcher,
        `/api/operator-workflow/items/${encodeURIComponent(normalizedEventId)}`
      ),
    loadPacketReadiness: (input: PacketReadinessInput) =>
      request<PacketReadiness>(fetcher, "/api/operator-workflow/packet-readiness", {
        body: JSON.stringify(input),
        headers: { accept: "application/json", "content-type": "application/json" },
        method: "POST"
      }),
    loadRunState: (runId: string) =>
      request<OperatorRunState>(
        fetcher,
        `/api/operator-workflow/runs/${encodeURIComponent(runId)}`
      ),
    loadVerificationOutcome: (runId: string) =>
      request<VerificationOutcome>(
        fetcher,
        `/api/operator-workflow/runs/${encodeURIComponent(runId)}/verification-outcome`
      )
  };
}

export type OperatorWorkflowApi = ReturnType<typeof createOperatorWorkflowApi>;

async function request<T>(fetcher: Fetcher, path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetcher(path, {
    headers: { accept: "application/json" },
    method: "GET",
    ...init
  });
  const payload = (await response.json()) as unknown;

  if (!response.ok) {
    throw new OperatorWorkflowApiError(response.status, payload);
  }

  return payload as T;
}

function parseErrorEnvelope(payload: unknown) {
  if (isRecord(payload) && isRecord(payload.error)) {
    return {
      code: stringValue(payload.error.code, "request_failed"),
      detail: stringValue(payload.error.detail, "The operator workflow request failed.")
    };
  }

  return {
    code: "request_failed",
    detail: "The operator workflow request failed."
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function stringValue(value: unknown, fallback: string) {
  return typeof value === "string" && value.length > 0 ? value : fallback;
}
