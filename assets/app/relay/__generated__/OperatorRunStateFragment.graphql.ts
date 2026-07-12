/**
 * @generated SignedSource<<675b0f9d955fef7fd8444f5f726acecb>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorRunStateFragment$data = {
  readonly activity: {
    readonly edges: ReadonlyArray<{
      readonly cursor: string | null | undefined;
      readonly node: {
        readonly kind: string;
        readonly stableId: string;
        readonly status: string;
        readonly title: string;
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly endCursor: string | null | undefined;
      readonly hasNextPage: boolean;
      readonly hasPreviousPage: boolean;
      readonly startCursor: string | null | undefined;
    };
  } | null | undefined;
  readonly allowedNextActions: ReadonlyArray<string>;
  readonly childSummary: {
    readonly evidenceCandidates: number;
    readonly evidenceItems: number;
    readonly hasMore: boolean;
    readonly missingEvidence: number;
    readonly observations: number;
    readonly requiredChecks: number;
    readonly verificationResults: number;
  };
  readonly commandAffordances: ReadonlyArray<{
    readonly blockerReasons: ReadonlyArray<string>;
    readonly identity: string;
    readonly inputDefaults: ReadonlyArray<{
      readonly field: string;
      readonly value: string | null | undefined;
      readonly values: ReadonlyArray<string>;
    }>;
    readonly reasonCodes: ReadonlyArray<string>;
    readonly requiredFields: ReadonlyArray<string>;
    readonly safeExplanation: string;
    readonly state: string;
    readonly targetIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
  }>;
  readonly commandOptions: {
    readonly evidenceAcceptance: ReadonlyArray<{
      readonly acceptancePolicyBasis: string;
      readonly evidenceCandidateId: string;
      readonly key: string;
      readonly label: string;
      readonly result: string;
    }>;
    readonly evidenceCandidate: ReadonlyArray<{
      readonly executionObservationId: string;
      readonly freshnessState: string;
      readonly key: string;
      readonly label: string;
      readonly sensitivity: string;
      readonly sourceIdentity: string;
      readonly sourceKind: string;
      readonly trustBasis: string;
      readonly verificationCheckId: string;
      readonly workRunId: string;
    }>;
    readonly observation: ReadonlyArray<{
      readonly defaultOutcomeKey: string;
      readonly freshnessState: string;
      readonly key: string;
      readonly label: string;
      readonly observationSourceIdentity: string;
      readonly observationSourceKind: string;
      readonly outcomes: ReadonlyArray<{
        readonly key: string;
        readonly label: string;
        readonly normalizedStatus: string;
        readonly observedStatus: string;
      }>;
      readonly runId: string;
      readonly sourceGraphItemId: string;
      readonly trustBasis: string;
      readonly verificationCheckId: string;
    }>;
    readonly waiver: ReadonlyArray<{
      readonly expectedExecutionState: string;
      readonly expectedVerificationState: string;
      readonly key: string;
      readonly label: string;
      readonly policyBasis: string;
      readonly runId: string;
      readonly runRequiredCheckId: string;
    }>;
  };
  readonly commandOptionsOverflow: boolean;
  readonly evidenceCandidates: ReadonlyArray<{
    readonly claim: string;
    readonly executionObservationId: string | null | undefined;
    readonly freshnessState: string;
    readonly id: string;
    readonly sourceIdentity: string;
    readonly sourceKind: string;
    readonly state: string;
    readonly trustBasis: string;
    readonly verificationCheckId: string;
  }>;
  readonly evidenceItems: ReadonlyArray<{
    readonly candidateId: string | null | undefined;
    readonly id: string;
    readonly state: string;
    readonly workRunId: string | null | undefined;
  }>;
  readonly missingEvidence: ReadonlyArray<{
    readonly reason: string;
    readonly verificationCheckId: string;
  }>;
  readonly observations: ReadonlyArray<{
    readonly freshnessState: string;
    readonly graphItemId: string | null | undefined;
    readonly id: string;
    readonly normalizedStatus: string;
    readonly sourceIdentity: string;
    readonly sourceKind: string;
    readonly trustBasis: string;
    readonly verificationCheckId: string | null | undefined;
  }>;
  readonly packet: {
    readonly id: string;
    readonly state: string;
    readonly title: string;
  };
  readonly packetVersion: {
    readonly id: string;
    readonly lifecycleState: string;
    readonly objective: string | null | undefined;
    readonly versionNumber: number;
  };
  readonly requiredChecks: ReadonlyArray<{
    readonly graphItemId: string | null | undefined;
    readonly id: string;
    readonly state: string;
    readonly verificationCheckId: string | null | undefined;
  }>;
  readonly run: {
    readonly aggregateState: string;
    readonly executionState: string;
    readonly id: string;
    readonly verificationState: string;
  };
  readonly sourceWatermark: string | null | undefined;
  readonly status: string;
  readonly type: string;
  readonly verificationResults: ReadonlyArray<{
    readonly actorPrincipalId: string | null | undefined;
    readonly evidenceItemId: string | null | undefined;
    readonly id: string;
    readonly operationId: string | null | undefined;
    readonly policyBasis: string | null | undefined;
    readonly result: string;
    readonly targetGraphItemId: string | null | undefined;
    readonly verificationCheckId: string;
    readonly workPacketVersionId: string | null | undefined;
    readonly workRunId: string | null | undefined;
  }>;
  readonly " $fragmentType": "OperatorRunStateFragment";
};
export type OperatorRunStateFragment$key = {
  readonly " $data"?: OperatorRunStateFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"OperatorRunStateFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "OperatorRunStateFragment"
};

(node as any).hash = "b07bf89a801e81a21f930c168015b45d";

export default node;
