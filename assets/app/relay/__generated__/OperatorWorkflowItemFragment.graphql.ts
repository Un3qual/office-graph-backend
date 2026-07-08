/**
 * @generated SignedSource<<cee10c7c6779f309fdd86add3f5495b4>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorWorkflowItemFragment$data = {
  readonly allowedNextActions: ReadonlyArray<string>;
  readonly auditTrace: {
    readonly operationId: string | null | undefined;
    readonly resourceCount: number;
    readonly resources: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
  };
  readonly blockerReasons: ReadonlyArray<string>;
  readonly graphLinks: ReadonlyArray<{
    readonly graphItemId: string | null | undefined;
    readonly id: string;
    readonly state: string | null | undefined;
    readonly title: string | null | undefined;
    readonly type: string;
  }>;
  readonly graphRelationships: ReadonlyArray<{
    readonly id: string;
    readonly relationshipType: string;
    readonly sourceGraphItemId: string;
    readonly targetGraphItemId: string;
  }>;
  readonly id: string;
  readonly normalizedEventId: string;
  readonly operationWatermark: string | null | undefined;
  readonly proposedChangeStatus: {
    readonly applied: number;
    readonly pending: number;
    readonly rejected: number;
    readonly total: number;
  };
  readonly reasonCodes: ReadonlyArray<string>;
  readonly revisionTrace: {
    readonly operationId: string | null | undefined;
    readonly resourceCount: number;
    readonly resources: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
  };
  readonly source: {
    readonly identity: string;
    readonly outcome: string;
    readonly replayIdentity: string;
  };
  readonly sourceWatermark: string | null | undefined;
  readonly status: string;
  readonly type: string;
  readonly " $fragmentType": "OperatorWorkflowItemFragment";
};
export type OperatorWorkflowItemFragment$key = {
  readonly " $data"?: OperatorWorkflowItemFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"OperatorWorkflowItemFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "type",
  "storageKey": null
},
v2 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "operationId",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "resourceCount",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "OperatorTypedId",
    "kind": "LinkedField",
    "name": "resources",
    "plural": true,
    "selections": [
      (v1/*:: as any*/),
      (v0/*:: as any*/)
    ],
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "OperatorWorkflowItemFragment",
  "selections": [
    (v0/*:: as any*/),
    (v1/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "normalizedEventId",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "status",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "reasonCodes",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorSource",
      "kind": "LinkedField",
      "name": "source",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "identity",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "replayIdentity",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "outcome",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorProposedChangeStatus",
      "kind": "LinkedField",
      "name": "proposedChangeStatus",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "pending",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "applied",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "rejected",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "total",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "blockerReasons",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "allowedNextActions",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "operationWatermark",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "sourceWatermark",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorGraphLink",
      "kind": "LinkedField",
      "name": "graphLinks",
      "plural": true,
      "selections": [
        (v1/*:: as any*/),
        (v0/*:: as any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "graphItemId",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "title",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "state",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorGraphRelationship",
      "kind": "LinkedField",
      "name": "graphRelationships",
      "plural": true,
      "selections": [
        (v0/*:: as any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "sourceGraphItemId",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "targetGraphItemId",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "relationshipType",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorTrace",
      "kind": "LinkedField",
      "name": "auditTrace",
      "plural": false,
      "selections": (v2/*:: as any*/),
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorTrace",
      "kind": "LinkedField",
      "name": "revisionTrace",
      "plural": false,
      "selections": (v2/*:: as any*/),
      "storageKey": null
    }
  ],
  "type": "OperatorWorkflowItem",
  "abstractKey": null
};
})();

(node as any).hash = "0c39bce9211be14340c14c42c5739de7";

export default node;
