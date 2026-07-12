/**
 * @generated SignedSource<<964e254dcfdb669825ad7bb7243dc4e4>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorRunStateQuery$variables = {
  activityAfter?: string | null | undefined;
  activityFirst: number;
  id: string;
};
export type OperatorRunStateQuery$data = {
  readonly operatorRunState: {
    readonly " $fragmentSpreads": FragmentRefs<"OperatorRunStateFragment">;
  };
};
export type OperatorRunStateQuery = {
  response: OperatorRunStateQuery$data;
  variables: OperatorRunStateQuery$variables;
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
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
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
  "kind": "ScalarField",
  "name": "status",
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
  "name": "id",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "key",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "runId",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "freshnessState",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "trustBasis",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "normalizedStatus",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "workRunId",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "executionObservationId",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceKind",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceIdentity",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "result",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "policyBasis",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "graphItemId",
  "storageKey": null
},
v23 = [
  (v4/*:: as any*/),
  (v5/*:: as any*/),
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
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "identity",
        "storageKey": null
      },
      (v6/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "reasonCodes",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "blockerReasons",
        "storageKey": null
      },
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
        "selections": [
          (v4/*:: as any*/),
          (v7/*:: as any*/)
        ],
        "storageKey": null
      }
    ],
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "OperatorRunCommandOptions",
    "kind": "LinkedField",
    "name": "commandOptions",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorObservationCommandOption",
        "kind": "LinkedField",
        "name": "observation",
        "plural": true,
        "selections": [
          (v8/*:: as any*/),
          (v9/*:: as any*/),
          (v10/*:: as any*/),
          (v11/*:: as any*/),
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
            "name": "observationSourceKind",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "observationSourceIdentity",
            "storageKey": null
          },
          (v12/*:: as any*/),
          (v13/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "defaultOutcomeKey",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorObservationOutcomeOption",
            "kind": "LinkedField",
            "name": "outcomes",
            "plural": true,
            "selections": [
              (v8/*:: as any*/),
              (v9/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "observedStatus",
                "storageKey": null
              },
              (v14/*:: as any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorEvidenceCandidateCommandOption",
        "kind": "LinkedField",
        "name": "evidenceCandidate",
        "plural": true,
        "selections": [
          (v8/*:: as any*/),
          (v9/*:: as any*/),
          (v15/*:: as any*/),
          (v11/*:: as any*/),
          (v16/*:: as any*/),
          (v17/*:: as any*/),
          (v18/*:: as any*/),
          (v12/*:: as any*/),
          (v13/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "sensitivity",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorEvidenceAcceptanceCommandOption",
        "kind": "LinkedField",
        "name": "evidenceAcceptance",
        "plural": true,
        "selections": [
          (v8/*:: as any*/),
          (v9/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "evidenceCandidateId",
            "storageKey": null
          },
          (v19/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "acceptancePolicyBasis",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorWaiverCommandOption",
        "kind": "LinkedField",
        "name": "waiver",
        "plural": true,
        "selections": [
          (v8/*:: as any*/),
          (v9/*:: as any*/),
          (v10/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "runRequiredCheckId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "expectedExecutionState",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "expectedVerificationState",
            "storageKey": null
          },
          (v20/*:: as any*/)
        ],
        "storageKey": null
      }
    ],
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "commandOptionsOverflow",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "OperatorRunChildSummary",
    "kind": "LinkedField",
    "name": "childSummary",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "requiredChecks",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "observations",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "evidenceCandidates",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "evidenceItems",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "verificationResults",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "missingEvidence",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "hasMore",
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
              (v21/*:: as any*/),
              (v5/*:: as any*/)
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
      (v7/*:: as any*/),
      (v21/*:: as any*/),
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
      (v7/*:: as any*/),
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
      (v7/*:: as any*/),
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
      (v7/*:: as any*/),
      (v22/*:: as any*/),
      (v11/*:: as any*/),
      (v6/*:: as any*/)
    ],
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "OperatorObservation",
    "kind": "LinkedField",
    "name": "observations",
    "plural": true,
    "selections": [
      (v7/*:: as any*/),
      (v11/*:: as any*/),
      (v22/*:: as any*/),
      (v14/*:: as any*/),
      (v12/*:: as any*/),
      (v13/*:: as any*/),
      (v17/*:: as any*/),
      (v18/*:: as any*/)
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
      (v7/*:: as any*/),
      (v11/*:: as any*/),
      (v16/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "claim",
        "storageKey": null
      },
      (v6/*:: as any*/),
      (v12/*:: as any*/),
      (v13/*:: as any*/),
      (v17/*:: as any*/),
      (v18/*:: as any*/)
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
      (v7/*:: as any*/),
      (v6/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "candidateId",
        "storageKey": null
      },
      (v15/*:: as any*/)
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
      (v7/*:: as any*/),
      (v19/*:: as any*/),
      (v11/*:: as any*/),
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
      (v20/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "targetGraphItemId",
        "storageKey": null
      },
      (v15/*:: as any*/),
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
      (v11/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "reason",
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
    "name": "OperatorRunStateQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*:: as any*/),
        "concreteType": "OperatorRunState",
        "kind": "LinkedField",
        "name": "operatorRunState",
        "plural": false,
        "selections": [
          {
            "kind": "InlineDataFragmentSpread",
            "name": "OperatorRunStateFragment",
            "selections": (v23/*:: as any*/),
            "args": [
              {
                "kind": "Variable",
                "name": "activityAfter",
                "variableName": "activityAfter"
              },
              {
                "kind": "Variable",
                "name": "activityFirst",
                "variableName": "activityFirst"
              }
            ],
            "argumentDefinitions": [
              (v0/*:: as any*/),
              {
                "defaultValue": 5,
                "kind": "LocalArgument",
                "name": "activityFirst"
              }
            ]
          }
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
      (v2/*:: as any*/),
      (v1/*:: as any*/),
      (v0/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "OperatorRunStateQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*:: as any*/),
        "concreteType": "OperatorRunState",
        "kind": "LinkedField",
        "name": "operatorRunState",
        "plural": false,
        "selections": (v23/*:: as any*/),
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "a57075773c2c9115c7b078f794705102",
    "id": null,
    "metadata": {},
    "name": "OperatorRunStateQuery",
    "operationKind": "query",
    "text": "query OperatorRunStateQuery(\n  $id: ID!\n  $activityFirst: Int!\n  $activityAfter: String\n) {\n  operatorRunState(id: $id) {\n    ...OperatorRunStateFragment_2q9Scy\n  }\n}\n\nfragment OperatorRunStateFragment_2q9Scy on OperatorRunState {\n  type\n  status\n  allowedNextActions\n  commandAffordances {\n    identity\n    state\n    reasonCodes\n    blockerReasons\n    safeExplanation\n    requiredFields\n    inputDefaults {\n      field\n      value\n      values\n    }\n    targetIds {\n      type\n      id\n    }\n  }\n  commandOptions {\n    observation {\n      key\n      label\n      runId\n      verificationCheckId\n      sourceGraphItemId\n      observationSourceKind\n      observationSourceIdentity\n      freshnessState\n      trustBasis\n      defaultOutcomeKey\n      outcomes {\n        key\n        label\n        observedStatus\n        normalizedStatus\n      }\n    }\n    evidenceCandidate {\n      key\n      label\n      workRunId\n      verificationCheckId\n      executionObservationId\n      sourceKind\n      sourceIdentity\n      freshnessState\n      trustBasis\n      sensitivity\n    }\n    evidenceAcceptance {\n      key\n      label\n      evidenceCandidateId\n      result\n      acceptancePolicyBasis\n    }\n    waiver {\n      key\n      label\n      runId\n      runRequiredCheckId\n      expectedExecutionState\n      expectedVerificationState\n      policyBasis\n    }\n  }\n  commandOptionsOverflow\n  childSummary {\n    requiredChecks\n    observations\n    evidenceCandidates\n    evidenceItems\n    verificationResults\n    missingEvidence\n    hasMore\n  }\n  activity(first: $activityFirst, after: $activityAfter) {\n    edges {\n      cursor\n      node {\n        kind\n        stableId\n        title\n        status\n      }\n    }\n    pageInfo {\n      hasNextPage\n      hasPreviousPage\n      startCursor\n      endCursor\n    }\n  }\n  sourceWatermark\n  packet {\n    id\n    title\n    state\n  }\n  packetVersion {\n    id\n    versionNumber\n    lifecycleState\n    objective\n  }\n  run {\n    id\n    aggregateState\n    executionState\n    verificationState\n  }\n  requiredChecks {\n    id\n    graphItemId\n    verificationCheckId\n    state\n  }\n  observations {\n    id\n    verificationCheckId\n    graphItemId\n    normalizedStatus\n    freshnessState\n    trustBasis\n    sourceKind\n    sourceIdentity\n  }\n  evidenceCandidates {\n    id\n    verificationCheckId\n    executionObservationId\n    claim\n    state\n    freshnessState\n    trustBasis\n    sourceKind\n    sourceIdentity\n  }\n  evidenceItems {\n    id\n    state\n    candidateId\n    workRunId\n  }\n  verificationResults {\n    id\n    result\n    verificationCheckId\n    evidenceItemId\n    operationId\n    actorPrincipalId\n    policyBasis\n    targetGraphItemId\n    workRunId\n    workPacketVersionId\n  }\n  missingEvidence {\n    verificationCheckId\n    reason\n  }\n}\n"
  }
};
})();

(node as any).hash = "b2ca614478e11d7e01412413679c2106";

export default node;
