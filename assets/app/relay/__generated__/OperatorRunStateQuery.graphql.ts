/**
 * @generated SignedSource<<bf7953fd7dfcf6b8b682f80d5314abcb>>
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
  projectionId: string;
  runId: string;
};
export type OperatorRunStateQuery$data = {
  readonly operatorRunState: {
    readonly " $fragmentSpreads": FragmentRefs<"OperatorRunStateFragment">;
  };
  readonly run: {
    readonly aggregateState: string;
    readonly evidenceCandidates: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly candidateState: string;
          readonly claim: string;
          readonly executionObservationId: string | null | undefined;
          readonly freshnessState: string;
          readonly id: string;
          readonly sourceIdentity: string;
          readonly sourceKind: string;
          readonly trustBasis: string;
          readonly verificationCheckId: string;
        };
      }> | null | undefined;
    };
    readonly evidenceItems: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly candidateId: string | null | undefined;
          readonly id: string;
          readonly state: string;
          readonly workRunId: string | null | undefined;
        };
      }> | null | undefined;
    };
    readonly executionObservations: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly freshnessState: string;
          readonly graphItemId: string | null | undefined;
          readonly id: string;
          readonly normalizedStatus: string;
          readonly sourceIdentity: string;
          readonly sourceKind: string;
          readonly trustBasis: string;
          readonly verificationCheckId: string | null | undefined;
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
          readonly verificationCheck: {
            readonly graphItemId: string;
            readonly id: string;
          };
          readonly verificationCheckId: string;
        };
      }> | null | undefined;
    };
    readonly verificationResults: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly actorPrincipalId: string | null | undefined;
          readonly evidenceItemId: string | null | undefined;
          readonly id: string;
          readonly operationId: string;
          readonly policyBasis: string | null | undefined;
          readonly result: string;
          readonly targetGraphItemId: string | null | undefined;
          readonly verificationCheckId: string;
          readonly workPacketVersionId: string | null | undefined;
          readonly workRunId: string | null | undefined;
        };
      }> | null | undefined;
    };
    readonly verificationState: string;
    readonly workPacket: {
      readonly id: string;
      readonly state: string;
      readonly title: string;
    };
    readonly workPacketVersion: {
      readonly id: string;
      readonly lifecycleState: string;
      readonly objective: string;
      readonly versionNumber: number;
    } | null | undefined;
  } | null | undefined;
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
  "name": "projectionId"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "runId"
},
v4 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "projectionId"
  }
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "type",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "status",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "key",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "runId",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "freshnessState",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "trustBasis",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "normalizedStatus",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "workRunId",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "executionObservationId",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceKind",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceIdentity",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "result",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "policyBasis",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v23 = [
  (v5/*:: as any*/),
  (v6/*:: as any*/),
  (v7/*:: as any*/),
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
      (v8/*:: as any*/),
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
          (v6/*:: as any*/),
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
          (v9/*:: as any*/),
          (v10/*:: as any*/),
          (v11/*:: as any*/),
          (v12/*:: as any*/),
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
          (v13/*:: as any*/),
          (v14/*:: as any*/),
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
              (v9/*:: as any*/),
              (v10/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "observedStatus",
                "storageKey": null
              },
              (v15/*:: as any*/)
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
          (v9/*:: as any*/),
          (v10/*:: as any*/),
          (v16/*:: as any*/),
          (v12/*:: as any*/),
          (v17/*:: as any*/),
          (v18/*:: as any*/),
          (v19/*:: as any*/),
          (v13/*:: as any*/),
          (v14/*:: as any*/),
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
          (v9/*:: as any*/),
          (v10/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "evidenceCandidateId",
            "storageKey": null
          },
          (v20/*:: as any*/),
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
          (v9/*:: as any*/),
          (v10/*:: as any*/),
          (v11/*:: as any*/),
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
          (v21/*:: as any*/)
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
    "concreteType": "OperatorRunCommandOptionSummary",
    "kind": "LinkedField",
    "name": "commandOptionSummary",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "observation",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "evidenceCandidate",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "evidenceAcceptance",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "waiver",
        "storageKey": null
      }
    ],
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
              (v22/*:: as any*/),
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
    "concreteType": "OperatorMissingEvidence",
    "kind": "LinkedField",
    "name": "missingEvidence",
    "plural": true,
    "selections": [
      (v12/*:: as any*/),
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
],
v24 = {
  "kind": "Literal",
  "name": "first",
  "value": 20
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "graphItemId",
  "storageKey": null
},
v26 = [
  (v24/*:: as any*/),
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
v27 = {
  "alias": "run",
  "args": [
    {
      "kind": "Variable",
      "name": "id",
      "variableName": "runId"
    }
  ],
  "concreteType": "WorkRun",
  "kind": "LinkedField",
  "name": "getWorkRun",
  "plural": false,
  "selections": [
    (v5/*:: as any*/),
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
        (v5/*:: as any*/),
        (v22/*:: as any*/),
        (v8/*:: as any*/)
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
        (v5/*:: as any*/),
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
        (v24/*:: as any*/),
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
                (v5/*:: as any*/),
                (v12/*:: as any*/),
                (v8/*:: as any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "VerificationCheck",
                  "kind": "LinkedField",
                  "name": "verificationCheck",
                  "plural": false,
                  "selections": [
                    (v5/*:: as any*/),
                    (v25/*:: as any*/)
                  ],
                  "storageKey": null
                }
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
      "args": (v26/*:: as any*/),
      "concreteType": "ExecutionObservationConnection",
      "kind": "LinkedField",
      "name": "executionObservations",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "ExecutionObservationEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "ExecutionObservation",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v5/*:: as any*/),
                (v12/*:: as any*/),
                (v25/*:: as any*/),
                (v15/*:: as any*/),
                (v13/*:: as any*/),
                (v14/*:: as any*/),
                (v18/*:: as any*/),
                (v19/*:: as any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "executionObservations(first:20,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"ASC\"}])"
    },
    {
      "alias": null,
      "args": (v26/*:: as any*/),
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
                (v5/*:: as any*/),
                (v12/*:: as any*/),
                (v17/*:: as any*/),
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
                },
                (v13/*:: as any*/),
                (v14/*:: as any*/),
                (v18/*:: as any*/),
                (v19/*:: as any*/)
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
      "args": (v26/*:: as any*/),
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
                (v5/*:: as any*/),
                (v8/*:: as any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "candidateId",
                  "storageKey": null
                },
                (v16/*:: as any*/)
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
      "args": (v26/*:: as any*/),
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
                (v5/*:: as any*/),
                (v20/*:: as any*/),
                (v12/*:: as any*/),
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
                (v21/*:: as any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "targetGraphItemId",
                  "storageKey": null
                },
                (v16/*:: as any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "workPacketVersionId",
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
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/),
      (v2/*:: as any*/),
      (v3/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": {
      "throwOnFieldError": true
    },
    "name": "OperatorRunStateQuery",
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
      },
      (v27/*:: as any*/)
    ],
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v2/*:: as any*/),
      (v3/*:: as any*/),
      (v1/*:: as any*/),
      (v0/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "OperatorRunStateQuery",
    "selections": [
      {
        "alias": null,
        "args": (v4/*:: as any*/),
        "concreteType": "OperatorRunState",
        "kind": "LinkedField",
        "name": "operatorRunState",
        "plural": false,
        "selections": (v23/*:: as any*/),
        "storageKey": null
      },
      (v27/*:: as any*/)
    ]
  },
  "params": {
    "cacheID": "830ea69d05012d2d12b437a86bbbbdbd",
    "id": null,
    "metadata": {},
    "name": "OperatorRunStateQuery",
    "operationKind": "query",
    "text": "query OperatorRunStateQuery(\n  $projectionId: ID!\n  $runId: ID!\n  $activityFirst: Int!\n  $activityAfter: String\n) {\n  operatorRunState(id: $projectionId) {\n    ...OperatorRunStateFragment_2q9Scy\n    id\n  }\n  run: getWorkRun(id: $runId) {\n    id\n    aggregateState\n    executionState\n    verificationState\n    workPacket {\n      id\n      title\n      state\n    }\n    workPacketVersion {\n      id\n      versionNumber\n      lifecycleState\n      objective\n    }\n    requiredChecks(first: 20, sort: [{field: POSITION, order: ASC}]) {\n      edges {\n        node {\n          id\n          verificationCheckId\n          state\n          verificationCheck {\n            id\n            graphItemId\n          }\n        }\n      }\n    }\n    executionObservations(first: 20, sort: [{field: INSERTED_AT, order: ASC}]) {\n      edges {\n        node {\n          id\n          verificationCheckId\n          graphItemId\n          normalizedStatus\n          freshnessState\n          trustBasis\n          sourceKind\n          sourceIdentity\n        }\n      }\n    }\n    evidenceCandidates(first: 20, sort: [{field: INSERTED_AT, order: ASC}]) {\n      edges {\n        node {\n          id\n          verificationCheckId\n          executionObservationId\n          claim\n          candidateState\n          freshnessState\n          trustBasis\n          sourceKind\n          sourceIdentity\n        }\n      }\n    }\n    evidenceItems(first: 20, sort: [{field: INSERTED_AT, order: ASC}]) {\n      edges {\n        node {\n          id\n          state\n          candidateId\n          workRunId\n        }\n      }\n    }\n    verificationResults(first: 20, sort: [{field: INSERTED_AT, order: ASC}]) {\n      edges {\n        node {\n          id\n          result\n          verificationCheckId\n          evidenceItemId\n          operationId\n          actorPrincipalId\n          policyBasis\n          targetGraphItemId\n          workRunId\n          workPacketVersionId\n        }\n      }\n    }\n  }\n}\n\nfragment OperatorRunStateFragment_2q9Scy on OperatorRunState {\n  id\n  type\n  status\n  allowedNextActions\n  commandAffordances {\n    identity\n    state\n    reasonCodes\n    blockerReasons\n    safeExplanation\n    requiredFields\n    inputDefaults {\n      field\n      value\n      values\n    }\n    targetIds {\n      type\n      id\n    }\n  }\n  commandOptions {\n    observation {\n      key\n      label\n      runId\n      verificationCheckId\n      sourceGraphItemId\n      observationSourceKind\n      observationSourceIdentity\n      freshnessState\n      trustBasis\n      defaultOutcomeKey\n      outcomes {\n        key\n        label\n        observedStatus\n        normalizedStatus\n      }\n    }\n    evidenceCandidate {\n      key\n      label\n      workRunId\n      verificationCheckId\n      executionObservationId\n      sourceKind\n      sourceIdentity\n      freshnessState\n      trustBasis\n      sensitivity\n    }\n    evidenceAcceptance {\n      key\n      label\n      evidenceCandidateId\n      result\n      acceptancePolicyBasis\n    }\n    waiver {\n      key\n      label\n      runId\n      runRequiredCheckId\n      expectedExecutionState\n      expectedVerificationState\n      policyBasis\n    }\n  }\n  commandOptionsOverflow\n  commandOptionSummary {\n    observation\n    evidenceCandidate\n    evidenceAcceptance\n    waiver\n  }\n  childSummary {\n    requiredChecks\n    observations\n    evidenceCandidates\n    evidenceItems\n    verificationResults\n    missingEvidence\n    hasMore\n  }\n  activity(first: $activityFirst, after: $activityAfter) {\n    edges {\n      cursor\n      node {\n        kind\n        stableId\n        title\n        status\n      }\n    }\n    pageInfo {\n      hasNextPage\n      hasPreviousPage\n      startCursor\n      endCursor\n    }\n  }\n  sourceWatermark\n  missingEvidence {\n    verificationCheckId\n    reason\n  }\n}\n"
  }
};
})();

(node as any).hash = "11c2dc8de1d7cc04d8f46a56ac53bbc1";

export default node;
