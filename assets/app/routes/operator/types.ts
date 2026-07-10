export type FetchStatus = "idle" | "fetching" | "paused";

export type QueryState<T> = {
  data: T | null;
  error: Error | null;
  fetchStatus: FetchStatus;
  isError: boolean;
  isPending: boolean;
  isSuccess: boolean;
};

export type OperatorInbox<TItem> = {
  type: "operator_inbox";
  empty: boolean;
  hasMore: boolean;
  limit: number;
  nextCursor: string | null;
  afterCursor: string | null;
  sourceWatermark: string | null;
  rows: TItem[];
};

export type OperatorInboxPage = {
  first: number;
  after: string | null;
};

export type PacketReadinessInput = {
  title: string;
  objective: string;
  contextSummary: string;
  requirements: string;
  successCriteria: string;
  autonomyPosture: string;
  sourceGraphItemIds: string[];
  verificationCheckIds: string[];
};

export type DerivedPacketReadiness<TCommand> = {
  type: "packet_readiness";
  ready: false;
  status: "blocked";
  allowedNextActions: string[];
  commandAffordances: TCommand[];
  blockerReasons: string[];
  sourceLinks: Array<{ title: string }>;
  requiredChecks: Array<{ state: string }>;
  sourceWatermark: string | null;
  isDerived: true;
};
