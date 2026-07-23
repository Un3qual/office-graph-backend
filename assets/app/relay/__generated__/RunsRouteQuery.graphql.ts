/**
 * @generated SignedSource<<a43c495f76d4b67413a903d10baa83b9>>
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
      readonly cursor: string | null | undefined;
      readonly node: {
        readonly aggregateState: string;
        readonly executionState: string;
        readonly id: string;
        readonly insertedAt: string;
        readonly objective: string | null | undefined;
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
        readonly sourceWatermark: string;
        readonly verificationState: string;
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
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "objective",
  "storageKey": null
},
v4 = [
  {
    "alias": null,
    "args": [
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
            "kind": "ScalarField",
            "name": "cursor",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorRunSummary",
            "kind": "LinkedField",
            "name": "node",
            "plural": false,
            "selections": [
              (v2/*:: as any*/),
              (v3/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "aggregateState",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "executionState",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "verificationState",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "insertedAt",
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
                "concreteType": "OperatorPacketRef",
                "kind": "LinkedField",
                "name": "packet",
                "plural": false,
                "selections": [
                  (v2/*:: as any*/),
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
                "concreteType": "OperatorPacketVersionRef",
                "kind": "LinkedField",
                "name": "packetVersion",
                "plural": false,
                "selections": [
                  (v2/*:: as any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "versionNumber",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "lifecycleState",
                    "storageKey": null
                  },
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
  }
];
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
    "selections": (v4/*:: as any*/),
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
    "selections": (v4/*:: as any*/)
  },
  "params": {
    "cacheID": "b878e6707cbcd2b24632ea6a39f77b75",
    "id": null,
    "metadata": {},
    "name": "RunsRouteQuery",
    "operationKind": "query",
    "text": "query RunsRouteQuery(\n  $first: Int!\n  $after: String\n) {\n  operatorRuns(first: $first, after: $after) {\n    edges {\n      cursor\n      node {\n        id\n        objective\n        aggregateState\n        executionState\n        verificationState\n        insertedAt\n        sourceWatermark\n        packet {\n          id\n          title\n          state\n        }\n        packetVersion {\n          id\n          versionNumber\n          lifecycleState\n          objective\n        }\n      }\n    }\n    pageInfo {\n      hasNextPage\n      hasPreviousPage\n      startCursor\n      endCursor\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "1731e118dedfc43eb656d154a6ddeab5";

export default node;
