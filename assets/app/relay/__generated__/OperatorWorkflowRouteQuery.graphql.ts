/**
 * @generated SignedSource<<671b92198284fcb53e66f9fe23e2b436>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorWorkflowRouteQuery$variables = {
  after?: string | null | undefined;
  first: number;
};
export type OperatorWorkflowRouteQuery$data = {
  readonly operatorManualIntakeAffordance: {
    readonly identity: string;
    readonly state: string;
  };
  readonly operatorWorkflowItems: {
    readonly edges: ReadonlyArray<{
      readonly cursor: string | null | undefined;
      readonly node: {
        readonly id: string;
        readonly " $fragmentSpreads": FragmentRefs<"OperatorWorkflowItemFragment">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly endCursor: string | null | undefined;
      readonly hasNextPage: boolean;
      readonly hasPreviousPage: boolean;
      readonly startCursor: string | null | undefined;
    };
  } | null | undefined;
};
export type OperatorWorkflowRouteQuery = {
  response: OperatorWorkflowRouteQuery$data;
  variables: OperatorWorkflowRouteQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "after"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "identity",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorCommandAffordance",
  "kind": "LinkedField",
  "name": "operatorManualIntakeAffordance",
  "plural": false,
  "selections": [
    (v2/*:: as any*/),
    (v3/*:: as any*/)
  ],
  "storageKey": null
},
v5 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "after"
  },
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "first"
  }
],
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "type",
  "storageKey": null
},
v9 = [
  (v8/*:: as any*/),
  (v7/*:: as any*/)
],
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "reasonCodes",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "blockerReasons",
  "storageKey": null
},
v12 = [
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
  }
],
v13 = [
  (v7/*:: as any*/),
  (v8/*:: as any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "OperatorTypedId",
    "kind": "LinkedField",
    "name": "typedId",
    "plural": false,
    "selections": (v9/*:: as any*/),
    "storageKey": null
  },
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
    "name": "duplicateOfId",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "status",
    "storageKey": null
  },
  (v10/*:: as any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "OperatorSource",
    "kind": "LinkedField",
    "name": "source",
    "plural": false,
    "selections": [
      (v2/*:: as any*/),
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
  (v11/*:: as any*/),
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
    "concreteType": "OperatorCommandAffordance",
    "kind": "LinkedField",
    "name": "commandAffordances",
    "plural": true,
    "selections": [
      (v2/*:: as any*/),
      (v3/*:: as any*/),
      (v10/*:: as any*/),
      (v11/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "safeExplanation",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "requiredFields",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandInputDefault",
        "kind": "LinkedField",
        "name": "inputDefaults",
        "plural": true,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "field",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "value",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "values",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorTypedId",
        "kind": "LinkedField",
        "name": "targetIds",
        "plural": true,
        "selections": (v9/*:: as any*/),
        "storageKey": null
      }
    ],
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
      (v8/*:: as any*/),
      (v7/*:: as any*/),
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
      (v3/*:: as any*/)
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
      (v7/*:: as any*/),
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
    "selections": (v12/*:: as any*/),
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "OperatorTrace",
    "kind": "LinkedField",
    "name": "revisionTrace",
    "plural": false,
    "selections": (v12/*:: as any*/),
    "storageKey": null
  }
],
v14 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasNextPage",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasPreviousPage",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "startCursor",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "endCursor",
      "storageKey": null
    }
  ],
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "OperatorWorkflowRouteQuery",
    "selections": [
      (v4/*:: as any*/),
      {
        "alias": null,
        "args": (v5/*:: as any*/),
        "concreteType": "OperatorWorkflowItemConnection",
        "kind": "LinkedField",
        "name": "operatorWorkflowItems",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorWorkflowItemEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              (v6/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorWorkflowItem",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  (v7/*:: as any*/),
                  {
                    "kind": "InlineDataFragmentSpread",
                    "name": "OperatorWorkflowItemFragment",
                    "selections": (v13/*:: as any*/),
                    "args": null,
                    "argumentDefinitions": []
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v14/*:: as any*/)
        ],
        "storageKey": null
      }
    ],
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v1/*:: as any*/),
      (v0/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "OperatorWorkflowRouteQuery",
    "selections": [
      (v4/*:: as any*/),
      {
        "alias": null,
        "args": (v5/*:: as any*/),
        "concreteType": "OperatorWorkflowItemConnection",
        "kind": "LinkedField",
        "name": "operatorWorkflowItems",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorWorkflowItemEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              (v6/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorWorkflowItem",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": (v13/*:: as any*/),
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v14/*:: as any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "1f5b675d5246ae2665bb91a58321548d",
    "id": null,
    "metadata": {},
    "name": "OperatorWorkflowRouteQuery",
    "operationKind": "query",
    "text": "query OperatorWorkflowRouteQuery(\n  $first: Int!\n  $after: String\n) {\n  operatorManualIntakeAffordance {\n    identity\n    state\n  }\n  operatorWorkflowItems(first: $first, after: $after) {\n    edges {\n      cursor\n      node {\n        id\n        ...OperatorWorkflowItemFragment\n      }\n    }\n    pageInfo {\n      hasNextPage\n      hasPreviousPage\n      startCursor\n      endCursor\n    }\n  }\n}\n\nfragment OperatorWorkflowItemFragment on OperatorWorkflowItem {\n  id\n  type\n  typedId {\n    type\n    id\n  }\n  normalizedEventId\n  duplicateOfId\n  status\n  reasonCodes\n  source {\n    identity\n    replayIdentity\n    outcome\n  }\n  proposedChangeStatus {\n    pending\n    applied\n    rejected\n    total\n  }\n  blockerReasons\n  allowedNextActions\n  commandAffordances {\n    identity\n    state\n    reasonCodes\n    blockerReasons\n    safeExplanation\n    requiredFields\n    inputDefaults {\n      field\n      value\n      values\n    }\n    targetIds {\n      type\n      id\n    }\n  }\n  operationWatermark\n  sourceWatermark\n  graphLinks {\n    type\n    id\n    graphItemId\n    title\n    state\n  }\n  graphRelationships {\n    id\n    sourceGraphItemId\n    targetGraphItemId\n    relationshipType\n  }\n  auditTrace {\n    operationId\n    resourceCount\n  }\n  revisionTrace {\n    operationId\n    resourceCount\n  }\n}\n"
  }
};
})();

(node as any).hash = "d1a30299cbac85b3be0ab0aacd405607";

export default node;
