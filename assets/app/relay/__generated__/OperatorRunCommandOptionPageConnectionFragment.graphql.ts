/**
 * @generated SignedSource<<5fbb66220bbeebba90f1fa5a90b007fe>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorRunCommandOptionPageConnectionFragment$data = {
  readonly edges: ReadonlyArray<{
    readonly cursor: string | null | undefined;
    readonly node: {
      readonly evidenceAcceptance: {
        readonly acceptancePolicyBasis: string;
        readonly evidenceCandidateId: string;
        readonly key: string;
        readonly label: string;
        readonly result: string;
      } | null | undefined;
      readonly evidenceCandidate: {
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
      } | null | undefined;
      readonly observation: {
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
      } | null | undefined;
      readonly waiver: {
        readonly expectedExecutionState: string;
        readonly expectedVerificationState: string;
        readonly key: string;
        readonly label: string;
        readonly policyBasis: string;
        readonly runId: string;
        readonly runRequiredCheckId: string;
      } | null | undefined;
    } | null | undefined;
  } | null | undefined> | null | undefined;
  readonly pageInfo: {
    readonly endCursor: string | null | undefined;
    readonly hasNextPage: boolean;
    readonly hasPreviousPage: boolean;
    readonly startCursor: string | null | undefined;
  };
  readonly " $fragmentType": "OperatorRunCommandOptionPageConnectionFragment";
};
export type OperatorRunCommandOptionPageConnectionFragment$key = {
  readonly " $data"?: OperatorRunCommandOptionPageConnectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"OperatorRunCommandOptionPageConnectionFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "OperatorRunCommandOptionPageConnectionFragment"
};

(node as any).hash = "61da6d03a1bdd9f712affff3e370def8";

export default node;
