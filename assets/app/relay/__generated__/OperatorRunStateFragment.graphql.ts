/**
 * @generated SignedSource<<58f7753e3a5ddc2b03aabd54daf5ac34>>
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
  readonly commandOptionSummary: {
    readonly evidenceAcceptance: number;
    readonly evidenceCandidate: number;
    readonly observation: number;
    readonly waiver: number;
  };
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
  readonly id: string;
  readonly missingEvidence: ReadonlyArray<{
    readonly reason: string;
    readonly verificationCheckId: string;
  }>;
  readonly sourceWatermark: string | null | undefined;
  readonly status: string;
  readonly type: string;
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

(node as any).hash = "74ebc79b11e8466eccd27e5e9bb4345f";

export default node;
