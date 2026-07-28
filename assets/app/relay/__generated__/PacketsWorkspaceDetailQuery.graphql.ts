/**
 * @generated SignedSource<<86d5c713c5519b5d295ff9322a3413ae>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type PacketsWorkspaceDetailQuery$variables = {
  id: string;
  versionAfter?: string | null | undefined;
  versionFirst: number;
};
export type PacketsWorkspaceDetailQuery$data = {
  readonly operatorPacketWorkspace: {
    readonly allowedNextActions: ReadonlyArray<string>;
    readonly blockerReasons: ReadonlyArray<string>;
    readonly commandAffordances: ReadonlyArray<{
      readonly blockerReasons: ReadonlyArray<string>;
      readonly decisionLinks: ReadonlyArray<{
        readonly id: string;
        readonly type: string;
      }>;
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
      readonly traceLinks: ReadonlyArray<{
        readonly id: string;
        readonly type: string;
      }>;
    }>;
    readonly ready: boolean;
    readonly sourceWatermark: string;
    readonly status: string;
  };
  readonly packet: {
    readonly currentVersion: {
      readonly autonomyPosture: string;
      readonly contextSummary: string;
      readonly id: string;
      readonly insertedAt: string;
      readonly lifecycleState: string;
      readonly objective: string;
      readonly operationId: string;
      readonly requiredChecks: ReadonlyArray<{
        readonly verificationCheckId: string;
      }>;
      readonly requirements: string;
      readonly sourceReferences: ReadonlyArray<{
        readonly graphItemId: string;
      }>;
      readonly successCriteria: string | null | undefined;
      readonly title: string;
      readonly versionNumber: number;
    } | null | undefined;
    readonly currentVersionId: string | null | undefined;
    readonly id: string;
    readonly operationId: string | null | undefined;
    readonly state: string;
    readonly title: string;
    readonly versions: {
      readonly edges: ReadonlyArray<{
        readonly cursor: string;
        readonly node: {
          readonly id: string;
          readonly lifecycleState: string;
          readonly title: string;
          readonly versionNumber: number;
        };
      }> | null | undefined;
      readonly pageInfo: {
        readonly endCursor: string | null | undefined;
        readonly hasNextPage: boolean;
        readonly hasPreviousPage: boolean;
        readonly startCursor: string | null | undefined;
      };
    };
  } | null | undefined;
};
export type PacketsWorkspaceDetailQuery = {
  response: PacketsWorkspaceDetailQuery$data;
  variables: PacketsWorkspaceDetailQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "versionAfter"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "versionFirst"
},
v3 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceWatermark",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "ready",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "status",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "blockerReasons",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "allowedNextActions",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v11 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "type",
    "storageKey": null
  },
  (v10/*:: as any*/)
],
v12 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorCommandAffordance",
  "kind": "LinkedField",
  "name": "commandAffordances",
  "plural": true,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "identity",
      "storageKey": null
    },
    (v9/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "reasonCodes",
      "storageKey": null
    },
    (v7/*:: as any*/),
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
      "selections": (v11/*:: as any*/),
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorTypedId",
      "kind": "LinkedField",
      "name": "traceLinks",
      "plural": true,
      "selections": (v11/*:: as any*/),
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "OperatorTypedId",
      "kind": "LinkedField",
      "name": "decisionLinks",
      "plural": true,
      "selections": (v11/*:: as any*/),
      "storageKey": null
    }
  ],
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "currentVersionId",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "operationId",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "versionNumber",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "lifecycleState",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "objective",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "contextSummary",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "requirements",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "successCriteria",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "autonomyPosture",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "insertedAt",
  "storageKey": null
},
v24 = [
  {
    "kind": "Literal",
    "name": "sort",
    "value": [
      {
        "field": "POSITION",
        "order": "ASC"
      }
    ]
  }
],
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "graphItemId",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": [
    {
      "kind": "Variable",
      "name": "after",
      "variableName": "versionAfter"
    },
    {
      "kind": "Variable",
      "name": "first",
      "variableName": "versionFirst"
    },
    {
      "kind": "Literal",
      "name": "sort",
      "value": [
        {
          "field": "VERSION_NUMBER",
          "order": "DESC"
        }
      ]
    }
  ],
  "concreteType": "WorkPacketVersionConnection",
  "kind": "LinkedField",
  "name": "versions",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "WorkPacketVersionEdge",
      "kind": "LinkedField",
      "name": "edges",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "cursor",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "WorkPacketVersion",
          "kind": "LinkedField",
          "name": "node",
          "plural": false,
          "selections": [
            (v10/*:: as any*/),
            (v16/*:: as any*/),
            (v17/*:: as any*/),
            (v13/*:: as any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
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
    }
  ],
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/),
      (v2/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": {
      "throwOnFieldError": true
    },
    "name": "PacketsWorkspaceDetailQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*:: as any*/),
        "concreteType": "OperatorPacketWorkspace",
        "kind": "LinkedField",
        "name": "operatorPacketWorkspace",
        "plural": false,
        "selections": [
          (v4/*:: as any*/),
          (v5/*:: as any*/),
          (v6/*:: as any*/),
          (v7/*:: as any*/),
          (v8/*:: as any*/),
          (v12/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": "packet",
        "args": (v3/*:: as any*/),
        "concreteType": "WorkPacket",
        "kind": "LinkedField",
        "name": "getWorkPacket",
        "plural": false,
        "selections": [
          (v10/*:: as any*/),
          (v13/*:: as any*/),
          (v9/*:: as any*/),
          (v14/*:: as any*/),
          (v15/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "WorkPacketVersion",
            "kind": "LinkedField",
            "name": "currentVersion",
            "plural": false,
            "selections": [
              (v10/*:: as any*/),
              (v16/*:: as any*/),
              (v17/*:: as any*/),
              (v13/*:: as any*/),
              (v18/*:: as any*/),
              (v19/*:: as any*/),
              (v20/*:: as any*/),
              (v21/*:: as any*/),
              (v22/*:: as any*/),
              (v15/*:: as any*/),
              (v23/*:: as any*/),
              {
                "alias": null,
                "args": (v24/*:: as any*/),
                "concreteType": "WorkPacketSourceReference",
                "kind": "LinkedField",
                "name": "sourceReferences",
                "plural": true,
                "selections": [
                  (v25/*:: as any*/)
                ],
                "storageKey": "sourceReferences(sort:[{\"field\":\"POSITION\",\"order\":\"ASC\"}])"
              },
              {
                "alias": null,
                "args": (v24/*:: as any*/),
                "concreteType": "WorkPacketRequiredCheck",
                "kind": "LinkedField",
                "name": "requiredChecks",
                "plural": true,
                "selections": [
                  (v26/*:: as any*/)
                ],
                "storageKey": "requiredChecks(sort:[{\"field\":\"POSITION\",\"order\":\"ASC\"}])"
              }
            ],
            "storageKey": null
          },
          (v27/*:: as any*/)
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
      (v0/*:: as any*/),
      (v2/*:: as any*/),
      (v1/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "PacketsWorkspaceDetailQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*:: as any*/),
        "concreteType": "OperatorPacketWorkspace",
        "kind": "LinkedField",
        "name": "operatorPacketWorkspace",
        "plural": false,
        "selections": [
          (v4/*:: as any*/),
          (v5/*:: as any*/),
          (v6/*:: as any*/),
          (v7/*:: as any*/),
          (v8/*:: as any*/),
          (v12/*:: as any*/),
          (v10/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": "packet",
        "args": (v3/*:: as any*/),
        "concreteType": "WorkPacket",
        "kind": "LinkedField",
        "name": "getWorkPacket",
        "plural": false,
        "selections": [
          (v10/*:: as any*/),
          (v13/*:: as any*/),
          (v9/*:: as any*/),
          (v14/*:: as any*/),
          (v15/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "WorkPacketVersion",
            "kind": "LinkedField",
            "name": "currentVersion",
            "plural": false,
            "selections": [
              (v10/*:: as any*/),
              (v16/*:: as any*/),
              (v17/*:: as any*/),
              (v13/*:: as any*/),
              (v18/*:: as any*/),
              (v19/*:: as any*/),
              (v20/*:: as any*/),
              (v21/*:: as any*/),
              (v22/*:: as any*/),
              (v15/*:: as any*/),
              (v23/*:: as any*/),
              {
                "alias": null,
                "args": (v24/*:: as any*/),
                "concreteType": "WorkPacketSourceReference",
                "kind": "LinkedField",
                "name": "sourceReferences",
                "plural": true,
                "selections": [
                  (v25/*:: as any*/),
                  (v10/*:: as any*/)
                ],
                "storageKey": "sourceReferences(sort:[{\"field\":\"POSITION\",\"order\":\"ASC\"}])"
              },
              {
                "alias": null,
                "args": (v24/*:: as any*/),
                "concreteType": "WorkPacketRequiredCheck",
                "kind": "LinkedField",
                "name": "requiredChecks",
                "plural": true,
                "selections": [
                  (v26/*:: as any*/),
                  (v10/*:: as any*/)
                ],
                "storageKey": "requiredChecks(sort:[{\"field\":\"POSITION\",\"order\":\"ASC\"}])"
              }
            ],
            "storageKey": null
          },
          (v27/*:: as any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "ca1ea5eedd8f59a33b87f3adf472c794",
    "id": null,
    "metadata": {},
    "name": "PacketsWorkspaceDetailQuery",
    "operationKind": "query",
    "text": "query PacketsWorkspaceDetailQuery(\n  $id: ID!\n  $versionFirst: Int!\n  $versionAfter: String\n) {\n  operatorPacketWorkspace(id: $id) {\n    sourceWatermark\n    ready\n    status\n    blockerReasons\n    allowedNextActions\n    commandAffordances {\n      identity\n      state\n      reasonCodes\n      blockerReasons\n      safeExplanation\n      requiredFields\n      inputDefaults {\n        field\n        value\n        values\n      }\n      targetIds {\n        type\n        id\n      }\n      traceLinks {\n        type\n        id\n      }\n      decisionLinks {\n        type\n        id\n      }\n    }\n    id\n  }\n  packet: getWorkPacket(id: $id) {\n    id\n    title\n    state\n    currentVersionId\n    operationId\n    currentVersion {\n      id\n      versionNumber\n      lifecycleState\n      title\n      objective\n      contextSummary\n      requirements\n      successCriteria\n      autonomyPosture\n      operationId\n      insertedAt\n      sourceReferences(sort: [{field: POSITION, order: ASC}]) {\n        graphItemId\n        id\n      }\n      requiredChecks(sort: [{field: POSITION, order: ASC}]) {\n        verificationCheckId\n        id\n      }\n    }\n    versions(first: $versionFirst, after: $versionAfter, sort: [{field: VERSION_NUMBER, order: DESC}]) {\n      edges {\n        cursor\n        node {\n          id\n          versionNumber\n          lifecycleState\n          title\n        }\n      }\n      pageInfo {\n        hasNextPage\n        hasPreviousPage\n        startCursor\n        endCursor\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "109e75720127663f447354ac644d96b6";

export default node;
