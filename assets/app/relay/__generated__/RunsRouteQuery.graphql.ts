/**
 * @generated SignedSource<<24511d019183e70a398cbfdff7453520>>
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
  readonly operatorRuns: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly aggregateState: string;
        readonly executionState: string;
        readonly id: string;
        readonly insertedAt: string;
        readonly objective: string | null | undefined;
        readonly packet: {
          readonly title: string;
        };
        readonly verificationState: string;
      } | null | undefined;
    } | null | undefined> | null | undefined;
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
        "concreteType": "OperatorRunSummaryConnection",
        "kind": "LinkedField",
        "name": "operatorRuns",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorRunSummaryEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorRunSummary",
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
                    "concreteType": "OperatorPacketRef",
                    "kind": "LinkedField",
                    "name": "packet",
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
        "concreteType": "OperatorRunSummaryConnection",
        "kind": "LinkedField",
        "name": "operatorRuns",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorRunSummaryEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorRunSummary",
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
                    "concreteType": "OperatorPacketRef",
                    "kind": "LinkedField",
                    "name": "packet",
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
    "cacheID": "da1cebdf66b67912fafc067561502140",
    "id": null,
    "metadata": {},
    "name": "RunsRouteQuery",
    "operationKind": "query",
    "text": "query RunsRouteQuery(\n  $first: Int!\n  $after: String\n) {\n  operatorRuns(first: $first, after: $after) {\n    edges {\n      node {\n        id\n        objective\n        aggregateState\n        executionState\n        verificationState\n        insertedAt\n        packet {\n          title\n          id\n        }\n      }\n    }\n    pageInfo {\n      hasNextPage\n      endCursor\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "8040f8a6afa93499878121bcae195971";

export default node;
