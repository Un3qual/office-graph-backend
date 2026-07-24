/**
 * @generated SignedSource<<d442484f38a445e0899147ef1d049033>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type RunActivityPageQuery$variables = {
  activityAfter?: string | null | undefined;
  activityFirst: number;
  id: string;
};
export type RunActivityPageQuery$data = {
  readonly operatorRunState: {
    readonly activity: {
      readonly edges: ReadonlyArray<{
        readonly cursor: string | null | undefined;
        readonly node: {
          readonly kind: string;
          readonly stableId: string;
          readonly status: string;
          readonly title: string;
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
};
export type RunActivityPageQuery = {
  response: RunActivityPageQuery$data;
  variables: RunActivityPageQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "activityAfter"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "activityFirst"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v3 = [
  {
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "id",
        "variableName": "id"
      }
    ],
    "concreteType": "OperatorRunState",
    "kind": "LinkedField",
    "name": "operatorRunState",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": [
          {
            "kind": "Variable",
            "name": "after",
            "variableName": "activityAfter"
          },
          {
            "kind": "Variable",
            "name": "first",
            "variableName": "activityFirst"
          }
        ],
        "concreteType": "OperatorRunActivityConnection",
        "kind": "LinkedField",
        "name": "activity",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorRunActivityEdge",
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
                "concreteType": "OperatorRunActivity",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "kind",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "stableId",
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
                    "name": "status",
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
    ],
    "storageKey": null
  }
];
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
    "name": "RunActivityPageQuery",
    "selections": (v3/*:: as any*/),
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v2/*:: as any*/),
      (v1/*:: as any*/),
      (v0/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "RunActivityPageQuery",
    "selections": (v3/*:: as any*/)
  },
  "params": {
    "cacheID": "5148363354ab70fd9c59db81332d298c",
    "id": null,
    "metadata": {},
    "name": "RunActivityPageQuery",
    "operationKind": "query",
    "text": "query RunActivityPageQuery(\n  $id: ID!\n  $activityFirst: Int!\n  $activityAfter: String\n) {\n  operatorRunState(id: $id) {\n    activity(first: $activityFirst, after: $activityAfter) {\n      edges {\n        cursor\n        node {\n          kind\n          stableId\n          title\n          status\n        }\n      }\n      pageInfo {\n        hasNextPage\n        hasPreviousPage\n        startCursor\n        endCursor\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "197cfea29335cc9b961091d53b75d6a3";

export default node;
