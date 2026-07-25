/**
 * @generated SignedSource<<314f4b0b29d42cb84a01c7ac61295eeb>>
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
    readonly evidenceCandidates: ReadonlyArray<{
      readonly claim: string;
      readonly id: string;
      readonly state: string;
    }>;
    readonly evidenceItems: ReadonlyArray<{
      readonly id: string;
      readonly state: string;
    }>;
    readonly missingEvidence: ReadonlyArray<{
      readonly reason: string;
      readonly verificationCheckId: string;
    }>;
    readonly packet: {
      readonly relayId: string;
      readonly title: string;
    };
    readonly packetVersion: {
      readonly lifecycleState: string;
      readonly objective: string | null | undefined;
      readonly versionNumber: number;
    } | null | undefined;
    readonly requiredChecks: ReadonlyArray<{
      readonly id: string;
      readonly state: string;
      readonly verificationCheckId: string | null | undefined;
    }>;
    readonly run: {
      readonly aggregateState: string;
      readonly executionState: string;
      readonly id: string;
      readonly verificationState: string;
    };
    readonly status: string;
    readonly verificationResults: ReadonlyArray<{
      readonly id: string;
      readonly policyBasis: string | null | undefined;
      readonly result: string;
      readonly verificationCheckId: string;
    }>;
  };
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
  "name": "relayId",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "versionNumber",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "lifecycleState",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "objective",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorRunRef",
  "kind": "LinkedField",
  "name": "run",
  "plural": false,
  "selections": [
    (v11/*:: as any*/),
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
    }
  ],
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorRequiredCheck",
  "kind": "LinkedField",
  "name": "requiredChecks",
  "plural": true,
  "selections": [
    (v11/*:: as any*/),
    (v13/*:: as any*/),
    (v14/*:: as any*/)
  ],
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorEvidenceCandidate",
  "kind": "LinkedField",
  "name": "evidenceCandidates",
  "plural": true,
  "selections": [
    (v11/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "claim",
      "storageKey": null
    },
    (v14/*:: as any*/)
  ],
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorEvidenceItem",
  "kind": "LinkedField",
  "name": "evidenceItems",
  "plural": true,
  "selections": [
    (v11/*:: as any*/),
    (v14/*:: as any*/)
  ],
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorVerificationResult",
  "kind": "LinkedField",
  "name": "verificationResults",
  "plural": true,
  "selections": [
    (v11/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "result",
      "storageKey": null
    },
    (v13/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "policyBasis",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorMissingEvidence",
  "kind": "LinkedField",
  "name": "missingEvidence",
  "plural": true,
  "selections": [
    (v13/*:: as any*/),
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
v20 = [
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
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorPacketRef",
            "kind": "LinkedField",
            "name": "packet",
            "plural": false,
            "selections": [
              (v6/*:: as any*/),
              (v7/*:: as any*/)
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
              (v8/*:: as any*/),
              (v9/*:: as any*/),
              (v10/*:: as any*/)
            ],
            "storageKey": null
          },
          (v12/*:: as any*/),
          (v15/*:: as any*/),
          (v16/*:: as any*/),
          (v17/*:: as any*/),
          (v18/*:: as any*/),
          (v19/*:: as any*/)
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
            "args": (v20/*:: as any*/),
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
                      (v7/*:: as any*/),
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
            "args": (v20/*:: as any*/),
            "filters": null,
            "handle": "connection",
            "key": "RunActivityFragment_activity",
            "kind": "LinkedHandle",
            "name": "activity"
          },
          (v5/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorPacketRef",
            "kind": "LinkedField",
            "name": "packet",
            "plural": false,
            "selections": [
              (v6/*:: as any*/),
              (v7/*:: as any*/),
              (v11/*:: as any*/)
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
              (v8/*:: as any*/),
              (v9/*:: as any*/),
              (v10/*:: as any*/),
              (v11/*:: as any*/)
            ],
            "storageKey": null
          },
          (v12/*:: as any*/),
          (v15/*:: as any*/),
          (v16/*:: as any*/),
          (v17/*:: as any*/),
          (v18/*:: as any*/),
          (v19/*:: as any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "accbf71bfe33d246b62b90d71511bd99",
    "id": null,
    "metadata": {},
    "name": "RunDetailQuery",
    "operationKind": "query",
    "text": "query RunDetailQuery(\n  $id: ID!\n  $activityFirst: Int!\n) {\n  ...RunActivityFragment_3DDDxQ\n  operatorRunState(id: $id) {\n    status\n    packet {\n      relayId\n      title\n      id\n    }\n    packetVersion {\n      versionNumber\n      lifecycleState\n      objective\n      id\n    }\n    run {\n      id\n      aggregateState\n      executionState\n      verificationState\n    }\n    requiredChecks {\n      id\n      verificationCheckId\n      state\n    }\n    evidenceCandidates {\n      id\n      claim\n      state\n    }\n    evidenceItems {\n      id\n      state\n    }\n    verificationResults {\n      id\n      result\n      verificationCheckId\n      policyBasis\n    }\n    missingEvidence {\n      verificationCheckId\n      reason\n    }\n  }\n}\n\nfragment RunActivityFragment_3DDDxQ on RootQueryType {\n  operatorRunState(id: $id) {\n    activity(first: $activityFirst) {\n      edges {\n        node {\n          kind\n          stableId\n          title\n          status\n          __typename\n        }\n        cursor\n      }\n      pageInfo {\n        hasNextPage\n        endCursor\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "0aca24fea487c4a59932b1798e8af035";

export default node;
