import type { OperatorPacketReadinessFragment$data } from "../../relay/__generated__/OperatorPacketReadinessFragment.graphql";
import type { OperatorRunStateFragment$data } from "../../relay/__generated__/OperatorRunStateFragment.graphql";
import type { OperatorWorkflowItemFragment$data } from "../../relay/__generated__/OperatorWorkflowItemFragment.graphql";

export type FetchStatus = "idle" | "fetching" | "paused";

export type QueryState<T> = {
  data: T | null;
  error: Error | null;
  fetchStatus: FetchStatus;
  isError: boolean;
  isPending: boolean;
  isSuccess: boolean;
};

export type CommandExecutionState = {
  error: Error | null;
  status: "idle" | "submitting" | "succeeded" | "failed";
};

export type OperatorWorkflowItem = Omit<OperatorWorkflowItemFragment$data, " $fragmentType">;
export type OperatorCommandAffordance = OperatorWorkflowItem["commandAffordances"][number];

export type OperatorInbox = {
  type: "operator_inbox";
  empty: boolean;
  hasMore: boolean;
  limit: number;
  nextCursor: string | null;
  afterCursor: string | null;
  sourceWatermark: string | null;
  rows: OperatorWorkflowItem[];
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
  primarySourceGraphItemId: string;
  primaryVerificationCheckId: string;
};

export type PacketReadiness = Omit<
  OperatorPacketReadinessFragment$data,
  " $fragmentType"
> & {
  isDerived?: boolean;
};

export type OperatorRunState = Omit<OperatorRunStateFragment$data, " $fragmentType">;

export type VerificationOutcome = {
  type: "verification_outcome";
  status: string;
  sourceWatermark: string | null;
  run: OperatorRunState["run"];
  verificationResults: OperatorRunState["verificationResults"];
  missingEvidence: OperatorRunState["missingEvidence"];
};
