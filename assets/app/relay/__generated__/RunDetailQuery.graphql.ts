/**
 * @generated SignedSource<<64913e447e7021e7c3b0462fa3668983>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type RunDetailQuery$variables = {
  activityAfter?: string | null | undefined;
  activityFirst: number;
  id: string;
};
export type RunDetailQuery$data = {
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
    readonly evidenceCandidates: ReadonlyArray<{
      readonly claim: string;
      readonly executionObservationId: string | null | undefined;
      readonly freshnessState: string;
      readonly id: string;
      readonly sourceIdentity: string;
      readonly sourceKind: string;
      readonly state: string;
      readonly trustBasis: string;
      readonly verificationCheckId: string;
    }>;
    readonly evidenceItems: ReadonlyArray<{
      readonly candidateId: string | null | undefined;
      readonly id: string;
      readonly state: string;
      readonly workRunId: string | null | undefined;
    }>;
    readonly missingEvidence: ReadonlyArray<{
      readonly reason: string;
      readonly verificationCheckId: string;
    }>;
    readonly packet: {
      readonly id: string;
      readonly relayId: string;
      readonly state: string;
      readonly title: string;
    };
    readonly packetVersion: {
      readonly id: string;
      readonly lifecycleState: string;
      readonly objective: string | null | undefined;
      readonly versionNumber: number;
    };
    readonly requiredChecks: ReadonlyArray<{
      readonly graphItemId: string | null | undefined;
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
    readonly sourceWatermark: string | null | undefined;
    readonly status: string;
    readonly type: string;
    readonly verificationResults: ReadonlyArray<{
      readonly actorPrincipalId: string | null | undefined;
      readonly evidenceItemId: string | null | undefined;
      readonly id: string;
      readonly operationId: string | null | undefined;
      readonly policyBasis: string | null | undefined;
      readonly result: string;
      readonly targetGraphItemId: string | null | undefined;
      readonly verificationCheckId: string;
      readonly workPacketVersionId: string | null | undefined;
      readonly workRunId: string | null | undefined;
    }>;
  };
};
export type RunDetailQuery = {
  response: RunDetailQuery$data;
  variables: RunDetailQuery$variables;
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
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "status",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "workRunId",
  "storageKey": null
},
v9 = [
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
        "args": null,
        "kind": "ScalarField",
        "name": "type",
        "storageKey": null
      },
      (v3/*:: as any*/),
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
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "relayId",
            "storageKey": null
          },
          (v5/*:: as any*/),
          (v6/*:: as any*/)
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
          (v4/*:: as any*/),
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
        "args": null,
        "concreteType": "OperatorRunRef",
        "kind": "LinkedField",
        "name": "run",
        "plural": false,
        "selections": [
          (v4/*:: as any*/),
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
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorRequiredCheck",
        "kind": "LinkedField",
        "name": "requiredChecks",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "graphItemId",
            "storageKey": null
          },
          (v7/*:: as any*/),
          (v6/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorEvidenceCandidate",
        "kind": "LinkedField",
        "name": "evidenceCandidates",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          (v7/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "executionObservationId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "claim",
            "storageKey": null
          },
          (v6/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "freshnessState",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "trustBasis",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "sourceKind",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "sourceIdentity",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorEvidenceItem",
        "kind": "LinkedField",
        "name": "evidenceItems",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          (v6/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "candidateId",
            "storageKey": null
          },
          (v8/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorVerificationResult",
        "kind": "LinkedField",
        "name": "verificationResults",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "result",
            "storageKey": null
          },
          (v7/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "evidenceItemId",
            "storageKey": null
          },
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
            "name": "actorPrincipalId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "policyBasis",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "targetGraphItemId",
            "storageKey": null
          },
          (v8/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "workPacketVersionId",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorMissingEvidence",
        "kind": "LinkedField",
        "name": "missingEvidence",
        "plural": true,
        "selections": [
          (v7/*:: as any*/),
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
                  (v5/*:: as any*/),
                  (v3/*:: as any*/)
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
    "metadata": null,
    "name": "RunDetailQuery",
    "selections": (v9/*:: as any*/),
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
    "name": "RunDetailQuery",
    "selections": (v9/*:: as any*/)
  },
  "params": {
    "cacheID": "d61d950f58277efc26c465d230d60d6c",
    "id": null,
    "metadata": {},
    "name": "RunDetailQuery",
    "operationKind": "query",
    "text": "query RunDetailQuery(\n  $id: ID!\n  $activityFirst: Int!\n  $activityAfter: String\n) {\n  operatorRunState(id: $id) {\n    type\n    status\n    sourceWatermark\n    packet {\n      id\n      relayId\n      title\n      state\n    }\n    packetVersion {\n      id\n      versionNumber\n      lifecycleState\n      objective\n    }\n    run {\n      id\n      aggregateState\n      executionState\n      verificationState\n    }\n    requiredChecks {\n      id\n      graphItemId\n      verificationCheckId\n      state\n    }\n    evidenceCandidates {\n      id\n      verificationCheckId\n      executionObservationId\n      claim\n      state\n      freshnessState\n      trustBasis\n      sourceKind\n      sourceIdentity\n    }\n    evidenceItems {\n      id\n      state\n      candidateId\n      workRunId\n    }\n    verificationResults {\n      id\n      result\n      verificationCheckId\n      evidenceItemId\n      operationId\n      actorPrincipalId\n      policyBasis\n      targetGraphItemId\n      workRunId\n      workPacketVersionId\n    }\n    missingEvidence {\n      verificationCheckId\n      reason\n    }\n    activity(first: $activityFirst, after: $activityAfter) {\n      edges {\n        cursor\n        node {\n          kind\n          stableId\n          title\n          status\n        }\n      }\n      pageInfo {\n        hasNextPage\n        hasPreviousPage\n        startCursor\n        endCursor\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "efa7ba2b9963beae6b29edd8f8886f82";

export default node;
