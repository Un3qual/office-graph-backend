/**
 * @generated SignedSource<<f72e81ce8cdea13aca7304692ebdaae8>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorRunStateFragment$data = {
  readonly allowedNextActions: ReadonlyArray<string>;
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
  }>;
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

(node as any).hash = "4c6fa1f3b6013e147ae2e35e6190cdd4";

export default node;
