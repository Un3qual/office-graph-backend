/**
 * @generated SignedSource<<f4230c884f6e5522e455b5a2d1328a6a>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type RunDetailQuery$variables = {
  activityFirst: number;
  id: string;
};
export type RunDetailQuery$data = {
  readonly operatorRunState: {
    readonly missingEvidence: ReadonlyArray<{
      readonly reason: string;
      readonly verificationCheckId: string;
    }>;
    readonly status: string;
  };
  readonly run: {
    readonly aggregateState: string;
    readonly evidenceCandidates: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly candidateState: string;
          readonly claim: string;
          readonly id: string;
        };
      }> | null | undefined;
    };
    readonly evidenceItems: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly id: string;
          readonly state: string;
        };
      }> | null | undefined;
    };
    readonly executionState: string;
    readonly id: string;
    readonly requiredChecks: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly id: string;
          readonly state: string;
          readonly verificationCheckId: string;
        };
      }> | null | undefined;
    };
    readonly verificationResults: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly id: string;
          readonly policyBasis: string | null | undefined;
          readonly result: string;
          readonly verificationCheckId: string;
        };
      }> | null | undefined;
    };
    readonly verificationState: string;
    readonly workPacket: {
      readonly id: string;
      readonly title: string;
    };
    readonly workPacketVersion: {
      readonly id: string;
      readonly lifecycleState: string;
      readonly objective: string;
      readonly versionNumber: number;
    } | null | undefined;
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"RunActivityFragment">;
};
export type RunDetailQuery = {
  response: RunDetailQuery$data;
  variables: RunDetailQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "activityFirst"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v2 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "activityFirst"
},
v3 = {
  "kind": "Variable",
  "name": "id",
  "variableName": "id"
},
v4 = [
  (v3/*:: as any*/)
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "status",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorMissingEvidence",
  "kind": "LinkedField",
  "name": "missingEvidence",
  "plural": true,
  "selections": [
    (v6/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "reason",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
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
  "kind": "Literal",
  "name": "first",
  "value": 20
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v12 = [
  (v10/*:: as any*/),
  {
    "kind": "Literal",
    "name": "sort",
    "value": [
      {
        "field": "INSERTED_AT",
        "order": "ASC"
      }
    ]
  }
],
v13 = {
  "alias": "run",
  "args": (v4/*:: as any*/),
  "concreteType": "WorkRun",
  "kind": "LinkedField",
  "name": "getWorkRun",
  "plural": false,
  "selections": [
    (v8/*:: as any*/),
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
      "concreteType": "WorkPacket",
      "kind": "LinkedField",
      "name": "workPacket",
      "plural": false,
      "selections": [
        (v8/*:: as any*/),
        (v9/*:: as any*/)
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "WorkPacketVersion",
      "kind": "LinkedField",
      "name": "workPacketVersion",
      "plural": false,
      "selections": [
        (v8/*:: as any*/),
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
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "objective",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        (v10/*:: as any*/),
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
      "concreteType": "RunRequiredCheckConnection",
      "kind": "LinkedField",
      "name": "requiredChecks",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "RunRequiredCheckEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "RunRequiredCheck",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v8/*:: as any*/),
                (v6/*:: as any*/),
                (v11/*:: as any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "requiredChecks(first:20,sort:[{\"field\":\"POSITION\",\"order\":\"ASC\"}])"
    },
    {
      "alias": null,
      "args": (v12/*:: as any*/),
      "concreteType": "EvidenceCandidateConnection",
      "kind": "LinkedField",
      "name": "evidenceCandidates",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "EvidenceCandidateEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "EvidenceCandidate",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v8/*:: as any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "claim",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "candidateState",
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "evidenceCandidates(first:20,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"ASC\"}])"
    },
    {
      "alias": null,
      "args": (v12/*:: as any*/),
      "concreteType": "EvidenceItemConnection",
      "kind": "LinkedField",
      "name": "evidenceItems",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "EvidenceItemEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "EvidenceItem",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v8/*:: as any*/),
                (v11/*:: as any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "evidenceItems(first:20,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"ASC\"}])"
    },
    {
      "alias": null,
      "args": (v12/*:: as any*/),
      "concreteType": "WorkGraphVerificationResultConnection",
      "kind": "LinkedField",
      "name": "verificationResults",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "WorkGraphVerificationResultEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "WorkGraphVerificationResult",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v8/*:: as any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "result",
                  "storageKey": null
                },
                (v6/*:: as any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "policyBasis",
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "verificationResults(first:20,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"ASC\"}])"
    }
  ],
  "storageKey": null
},
v14 = [
  (v2/*:: as any*/)
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
    "name": "RunDetailQuery",
    "selections": [
      {
        "args": [
          (v2/*:: as any*/),
          (v3/*:: as any*/)
        ],
        "kind": "FragmentSpread",
        "name": "RunActivityFragment"
      },
      {
        "alias": null,
        "args": (v4/*:: as any*/),
        "concreteType": "OperatorRunState",
        "kind": "LinkedField",
        "name": "operatorRunState",
        "plural": false,
        "selections": [
          (v5/*:: as any*/),
          (v7/*:: as any*/)
        ],
        "storageKey": null
      },
      (v13/*:: as any*/)
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
    "name": "RunDetailQuery",
    "selections": [
      {
        "alias": null,
        "args": (v4/*:: as any*/),
        "concreteType": "OperatorRunState",
        "kind": "LinkedField",
        "name": "operatorRunState",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v14/*:: as any*/),
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
                      (v9/*:: as any*/),
                      (v5/*:: as any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "__typename",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "cursor",
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
                    "name": "endCursor",
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
            "args": (v14/*:: as any*/),
            "filters": null,
            "handle": "connection",
            "key": "RunActivityFragment_activity",
            "kind": "LinkedHandle",
            "name": "activity"
          },
          (v5/*:: as any*/),
          (v7/*:: as any*/)
        ],
        "storageKey": null
      },
      (v13/*:: as any*/)
    ]
  },
  "params": {
    "cacheID": "b0508c409e5e4faff24bd9964b27dc21",
    "id": null,
    "metadata": {},
    "name": "RunDetailQuery",
    "operationKind": "query",
    "text": "query RunDetailQuery(\n  $id: ID!\n  $activityFirst: Int!\n) {\n  ...RunActivityFragment_3DDDxQ\n  operatorRunState(id: $id) {\n    status\n    missingEvidence {\n      verificationCheckId\n      reason\n    }\n  }\n  run: getWorkRun(id: $id) {\n    id\n    aggregateState\n    executionState\n    verificationState\n    workPacket {\n      id\n      title\n    }\n    workPacketVersion {\n      id\n      versionNumber\n      lifecycleState\n      objective\n    }\n    requiredChecks(first: 20, sort: [{field: POSITION, order: ASC}]) {\n      edges {\n        node {\n          id\n          verificationCheckId\n          state\n        }\n      }\n    }\n    evidenceCandidates(first: 20, sort: [{field: INSERTED_AT, order: ASC}]) {\n      edges {\n        node {\n          id\n          claim\n          candidateState\n        }\n      }\n    }\n    evidenceItems(first: 20, sort: [{field: INSERTED_AT, order: ASC}]) {\n      edges {\n        node {\n          id\n          state\n        }\n      }\n    }\n    verificationResults(first: 20, sort: [{field: INSERTED_AT, order: ASC}]) {\n      edges {\n        node {\n          id\n          result\n          verificationCheckId\n          policyBasis\n        }\n      }\n    }\n  }\n}\n\nfragment RunActivityFragment_3DDDxQ on RootQueryType {\n  operatorRunState(id: $id) {\n    activity(first: $activityFirst) {\n      edges {\n        node {\n          kind\n          stableId\n          title\n          status\n          __typename\n        }\n        cursor\n      }\n      pageInfo {\n        hasNextPage\n        endCursor\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "f413ecfe0925103077bdbfe149123ded";

export default node;
