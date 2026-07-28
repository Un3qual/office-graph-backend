/**
 * @generated SignedSource<<b0c47a002bf9be46c44251205d5c36c1>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type RunsRouteQuery$variables = {
  after?: string | null | undefined;
  first: number;
};
export type RunsRouteQuery$data = {
  readonly listWorkRuns: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly aggregateState: string;
        readonly executionState: string;
        readonly id: string;
        readonly insertedAt: string;
        readonly objective: string | null | undefined;
        readonly verificationState: string;
        readonly workPacket: {
          readonly title: string;
        };
      };
    }> | null | undefined;
    readonly pageInfo: {
      readonly endCursor: string | null | undefined;
      readonly hasNextPage: boolean;
    };
  } | null | undefined;
};
export type RunsRouteQuery = {
  response: RunsRouteQuery$data;
  variables: RunsRouteQuery$variables;
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
v2 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "after"
  },
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "first"
  },
  {
    "kind": "Literal",
    "name": "sort",
    "value": [
      {
        "field": "INSERTED_AT",
        "order": "DESC"
      }
    ]
  }
],
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
  "name": "objective",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "aggregateState",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "executionState",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationState",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "insertedAt",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v10 = {
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
    "metadata": {
      "throwOnFieldError": true
    },
    "name": "RunsRouteQuery",
    "selections": [
      {
        "alias": null,
        "args": (v2/*:: as any*/),
        "concreteType": "WorkRunConnection",
        "kind": "LinkedField",
        "name": "listWorkRuns",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "WorkRunEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "WorkRun",
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
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "WorkPacket",
                    "kind": "LinkedField",
                    "name": "workPacket",
                    "plural": false,
                    "selections": [
                      (v9/*:: as any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v10/*:: as any*/)
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
    "name": "RunsRouteQuery",
    "selections": [
      {
        "alias": null,
        "args": (v2/*:: as any*/),
        "concreteType": "WorkRunConnection",
        "kind": "LinkedField",
        "name": "listWorkRuns",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "WorkRunEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "WorkRun",
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
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "WorkPacket",
                    "kind": "LinkedField",
                    "name": "workPacket",
                    "plural": false,
                    "selections": [
                      (v9/*:: as any*/),
                      (v3/*:: as any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v10/*:: as any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "dd68ee9ff9c18983f196df75de6cbd91",
    "id": null,
    "metadata": {},
    "name": "RunsRouteQuery",
    "operationKind": "query",
    "text": "query RunsRouteQuery(\n  $first: Int!\n  $after: String\n) {\n  listWorkRuns(first: $first, after: $after, sort: [{field: INSERTED_AT, order: DESC}]) {\n    edges {\n      node {\n        id\n        objective\n        aggregateState\n        executionState\n        verificationState\n        insertedAt\n        workPacket {\n          title\n          id\n        }\n      }\n    }\n    pageInfo {\n      hasNextPage\n      endCursor\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "0520186dac5626f5322bf847a41b1164";

export default node;
