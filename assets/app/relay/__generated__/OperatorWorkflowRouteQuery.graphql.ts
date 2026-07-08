/**
 * @generated SignedSource<<fef766b558cd6e666bcd5c2d9cda5caa>>
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
  "name": "cursor",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "type",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorTypedId",
  "kind": "LinkedField",
  "name": "typedId",
  "plural": false,
  "selections": [
    (v4/*:: as any*/),
    (v3/*:: as any*/)
  ],
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "normalizedEventId",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "duplicateOfId",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "status",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "reasonCodes",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "identity",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorSource",
  "kind": "LinkedField",
  "name": "source",
  "plural": false,
  "selections": [
    (v10/*:: as any*/),
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
v12 = {
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
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "blockerReasons",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "allowedNextActions",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorCommandAffordance",
  "kind": "LinkedField",
  "name": "commandAffordances",
  "plural": true,
  "selections": [
    (v10/*:: as any*/),
    (v15/*:: as any*/),
    (v9/*:: as any*/),
    (v13/*:: as any*/),
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
    }
  ],
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "operationWatermark",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceWatermark",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorGraphLink",
  "kind": "LinkedField",
  "name": "graphLinks",
  "plural": true,
  "selections": [
    (v4/*:: as any*/),
    (v3/*:: as any*/),
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
    (v15/*:: as any*/)
  ],
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorGraphRelationship",
  "kind": "LinkedField",
  "name": "graphRelationships",
  "plural": true,
  "selections": [
    (v3/*:: as any*/),
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
v21 = [
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
v22 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorTrace",
  "kind": "LinkedField",
  "name": "auditTrace",
  "plural": false,
  "selections": (v21/*:: as any*/),
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorTrace",
  "kind": "LinkedField",
  "name": "revisionTrace",
  "plural": false,
  "selections": (v21/*:: as any*/),
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v25 = {
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
},
v26 = [
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
];
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
      {
        "alias": "operatorWorkflowItems",
        "args": null,
        "concreteType": "OperatorWorkflowItemConnection",
        "kind": "LinkedField",
        "name": "__OperatorWorkflowRoute_operatorWorkflowItems_connection",
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
              (v2/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorWorkflowItem",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  (v3/*:: as any*/),
                  {
                    "kind": "InlineDataFragmentSpread",
                    "name": "OperatorWorkflowItemFragment",
                    "selections": [
                      (v3/*:: as any*/),
                      (v4/*:: as any*/),
                      (v5/*:: as any*/),
                      (v6/*:: as any*/),
                      (v7/*:: as any*/),
                      (v8/*:: as any*/),
                      (v9/*:: as any*/),
                      (v11/*:: as any*/),
                      (v12/*:: as any*/),
                      (v13/*:: as any*/),
                      (v14/*:: as any*/),
                      (v16/*:: as any*/),
                      (v17/*:: as any*/),
                      (v18/*:: as any*/),
                      (v19/*:: as any*/),
                      (v20/*:: as any*/),
                      (v22/*:: as any*/),
                      (v23/*:: as any*/)
                    ],
                    "args": null,
                    "argumentDefinitions": []
                  },
                  (v24/*:: as any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v25/*:: as any*/)
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
      {
        "alias": null,
        "args": (v26/*:: as any*/),
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
              (v2/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorWorkflowItem",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  (v3/*:: as any*/),
                  (v4/*:: as any*/),
                  (v5/*:: as any*/),
                  (v6/*:: as any*/),
                  (v7/*:: as any*/),
                  (v8/*:: as any*/),
                  (v9/*:: as any*/),
                  (v11/*:: as any*/),
                  (v12/*:: as any*/),
                  (v13/*:: as any*/),
                  (v14/*:: as any*/),
                  (v16/*:: as any*/),
                  (v17/*:: as any*/),
                  (v18/*:: as any*/),
                  (v19/*:: as any*/),
                  (v20/*:: as any*/),
                  (v22/*:: as any*/),
                  (v23/*:: as any*/),
                  (v24/*:: as any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v25/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": (v26/*:: as any*/),
        "filters": null,
        "handle": "connection",
        "key": "OperatorWorkflowRoute_operatorWorkflowItems",
        "kind": "LinkedHandle",
        "name": "operatorWorkflowItems"
      }
    ]
  },
  "params": {
    "cacheID": "74ac5104b9c459bf9af4709a9f495bdd",
    "id": null,
    "metadata": {
      "connection": [
        {
          "count": "first",
          "cursor": "after",
          "direction": "forward",
          "path": [
            "operatorWorkflowItems"
          ]
        }
      ]
    },
    "name": "OperatorWorkflowRouteQuery",
    "operationKind": "query",
    "text": "query OperatorWorkflowRouteQuery(\n  $first: Int!\n  $after: String\n) {\n  operatorWorkflowItems(first: $first, after: $after) {\n    edges {\n      cursor\n      node {\n        id\n        ...OperatorWorkflowItemFragment\n        __typename\n      }\n    }\n    pageInfo {\n      hasNextPage\n      hasPreviousPage\n      startCursor\n      endCursor\n    }\n  }\n}\n\nfragment OperatorWorkflowItemFragment on OperatorWorkflowItem {\n  id\n  type\n  typedId {\n    type\n    id\n  }\n  normalizedEventId\n  duplicateOfId\n  status\n  reasonCodes\n  source {\n    identity\n    replayIdentity\n    outcome\n  }\n  proposedChangeStatus {\n    pending\n    applied\n    rejected\n    total\n  }\n  blockerReasons\n  allowedNextActions\n  commandAffordances {\n    identity\n    state\n    reasonCodes\n    blockerReasons\n    safeExplanation\n    requiredFields\n  }\n  operationWatermark\n  sourceWatermark\n  graphLinks {\n    type\n    id\n    graphItemId\n    title\n    state\n  }\n  graphRelationships {\n    id\n    sourceGraphItemId\n    targetGraphItemId\n    relationshipType\n  }\n  auditTrace {\n    operationId\n    resourceCount\n  }\n  revisionTrace {\n    operationId\n    resourceCount\n  }\n}\n"
  }
};
})();

(node as any).hash = "be3e10235a10ca3672e107febfed6eca";

export default node;
