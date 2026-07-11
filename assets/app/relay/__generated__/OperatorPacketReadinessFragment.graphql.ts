/**
 * @generated SignedSource<<97084be70821f9e993563e8b1ee307eb>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorPacketReadinessFragment$data = {
  readonly allowedNextActions: ReadonlyArray<string>;
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
  readonly ready: boolean;
  readonly requiredChecks: ReadonlyArray<{
    readonly state: string;
  }>;
  readonly sourceLinks: ReadonlyArray<{
    readonly title: string;
  }>;
  readonly sourceWatermark: string | null | undefined;
  readonly status: string;
  readonly type: string;
  readonly " $fragmentType": "OperatorPacketReadinessFragment";
};
export type OperatorPacketReadinessFragment$key = {
  readonly " $data"?: OperatorPacketReadinessFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"OperatorPacketReadinessFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "OperatorPacketReadinessFragment"
};

(node as any).hash = "61718bad1d4f7268f20c84add5cc20d2";

export default node;
