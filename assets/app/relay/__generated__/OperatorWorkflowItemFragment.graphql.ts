/**
 * @generated SignedSource<<c442ceb628fcafd107bf011971d6c044>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorWorkflowItemFragment$data = {
  readonly allowedNextActions: ReadonlyArray<string>;
  readonly auditTrace: {
    readonly operationId: string | null | undefined;
    readonly resourceCount: number;
  };
  readonly blockerReasons: ReadonlyArray<string>;
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
  readonly duplicateOfId: string | null | undefined;
  readonly graphLinks: ReadonlyArray<{
    readonly graphItemId: string | null | undefined;
    readonly id: string;
    readonly state: string | null | undefined;
    readonly title: string | null | undefined;
    readonly type: string;
  }>;
  readonly graphRelationships: ReadonlyArray<{
    readonly definitionKey: string;
    readonly id: string;
    readonly sourceGraphItemId: string;
    readonly targetGraphItemId: string;
  }>;
  readonly id: string;
  readonly normalizedEventId: string;
  readonly operationWatermark: string | null | undefined;
  readonly proposedActionPreviews: ReadonlyArray<{
    readonly action: string;
    readonly status: string;
    readonly title: string;
  }>;
  readonly proposedChangeStatus: {
    readonly applied: number;
    readonly pending: number;
    readonly rejected: number;
    readonly total: number;
  };
  readonly reasonCodes: ReadonlyArray<string>;
  readonly relationshipSummary: {
    readonly graphLinks: number;
    readonly graphRelationships: number;
    readonly hasMore: boolean;
  };
  readonly revisionTrace: {
    readonly operationId: string | null | undefined;
    readonly resourceCount: number;
  };
  readonly source: {
    readonly identity: string;
    readonly outcome: string;
    readonly replayIdentity: string;
  };
  readonly sourceSummary: string;
  readonly sourceWatermark: string | null | undefined;
  readonly status: string;
  readonly title: string;
  readonly type: string;
  readonly typedId: {
    readonly id: string;
    readonly type: string;
  };
  readonly " $fragmentType": "OperatorWorkflowItemFragment";
};
export type OperatorWorkflowItemFragment$key = {
  readonly " $data"?: OperatorWorkflowItemFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"OperatorWorkflowItemFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "OperatorWorkflowItemFragment"
};

(node as any).hash = "6f86e2db6479216cb72f257ff6bf332c";

export default node;
