import type { RunActivityFragment$key } from "../../relay/__generated__/RunActivityFragment.graphql";
import type { RunDetailQuery as RunDetailOperation } from "../../relay/__generated__/RunDetailQuery.graphql";
import type { RunsRouteQuery as RunsRouteOperation } from "../../relay/__generated__/RunsRouteQuery.graphql";

type RunsConnection = NonNullable<RunsRouteOperation["response"]["listWorkRuns"]>;
type RunsEdge = NonNullable<NonNullable<RunsConnection["edges"]>[number]>;

export type RunSummary = NonNullable<RunsEdge["node"]>;
type RunDetailResponse = RunDetailOperation["response"];
type RunProjection = NonNullable<RunDetailResponse["operatorRunState"]>;
type RunResource = NonNullable<RunDetailResponse["run"]>;
type RunRequiredCheckConnection = RunResource["requiredChecks"];
type EvidenceCandidateConnection = RunResource["evidenceCandidates"];
type EvidenceItemConnection = RunResource["evidenceItems"];
type VerificationResultConnection = RunResource["verificationResults"];
type ConnectionNode<TConnection extends { readonly edges?: ReadonlyArray<unknown> | null }> =
  NonNullable<NonNullable<TConnection["edges"]>[number]> extends {
    readonly node: infer TNode;
  }
    ? NonNullable<TNode>
    : never;

export type RunDetailState = RunProjection & {
  packet: {
    relayId: string;
    title: string;
  };
  packetVersion: RunResource["workPacketVersion"];
  run: Pick<RunResource, "id" | "aggregateState" | "executionState" | "verificationState">;
  requiredChecks: Array<ConnectionNode<RunRequiredCheckConnection>>;
  evidenceCandidates: Array<
    Omit<ConnectionNode<EvidenceCandidateConnection>, "candidateState"> & { state: string }
  >;
  evidenceItems: Array<ConnectionNode<EvidenceItemConnection>>;
  verificationResults: Array<ConnectionNode<VerificationResultConnection>>;
  relationshipOverflow: {
    evidenceCandidates: boolean;
    evidenceItems: boolean;
    requiredChecks: boolean;
    verificationResults: boolean;
  };
};
export type RunDetailResult = {
  activityRef: RunActivityFragment$key;
  detail: RunDetailState;
};

export type RunsPage = {
  first: number;
  after: string | null;
};

export type RunsConnectionState = {
  hasNextPage: boolean;
  nextCursor: string | null;
  rows: RunSummary[];
};
