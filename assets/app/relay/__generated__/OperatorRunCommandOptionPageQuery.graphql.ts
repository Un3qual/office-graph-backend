/**
 * @generated SignedSource<<e2d9f6a57406172ae1e483019dbe5f6c>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type OperatorRunCommandOptionPageQuery$variables = {
  after?: string | null | undefined;
  first: number;
  id: string;
  kind: string;
};
export type OperatorRunCommandOptionPageQuery$data = {
  readonly operatorRunState: {
    readonly commandOptionPage: {
      readonly edges: ReadonlyArray<{
        readonly cursor: string | null | undefined;
        readonly node: {
          readonly evidenceAcceptance: {
            readonly acceptancePolicyBasis: string;
            readonly evidenceCandidateId: string;
            readonly key: string;
            readonly label: string;
            readonly result: string;
          } | null | undefined;
          readonly evidenceCandidate: {
            readonly executionObservationId: string;
            readonly freshnessState: string;
            readonly key: string;
            readonly label: string;
            readonly sensitivity: string;
            readonly sourceIdentity: string;
            readonly sourceKind: string;
            readonly trustBasis: string;
            readonly verificationCheckId: string;
            readonly workRunId: string;
          } | null | undefined;
          readonly observation: {
            readonly defaultOutcomeKey: string;
            readonly freshnessState: string;
            readonly key: string;
            readonly label: string;
            readonly observationSourceIdentity: string;
            readonly observationSourceKind: string;
            readonly outcomes: ReadonlyArray<{
              readonly key: string;
              readonly label: string;
              readonly normalizedStatus: string;
              readonly observedStatus: string;
            }>;
            readonly runId: string;
            readonly sourceGraphItemId: string;
            readonly trustBasis: string;
            readonly verificationCheckId: string;
          } | null | undefined;
          readonly waiver: {
            readonly expectedExecutionState: string;
            readonly expectedVerificationState: string;
            readonly key: string;
            readonly label: string;
            readonly policyBasis: string;
            readonly runId: string;
            readonly runRequiredCheckId: string;
          } | null | undefined;
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
export type OperatorRunCommandOptionPageQuery = {
  response: OperatorRunCommandOptionPageQuery$data;
  variables: OperatorRunCommandOptionPageQuery$variables;
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
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "kind"
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "key",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "runId",
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
  "name": "freshnessState",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "trustBasis",
  "storageKey": null
},
v10 = [
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
            "variableName": "after"
          },
          {
            "kind": "Variable",
            "name": "first",
            "variableName": "first"
          },
          {
            "kind": "Variable",
            "name": "kind",
            "variableName": "kind"
          }
        ],
        "concreteType": "OperatorRunCommandOptionChoiceConnection",
        "kind": "LinkedField",
        "name": "commandOptionPage",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorRunCommandOptionChoiceEdge",
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
                "concreteType": "OperatorRunCommandOptionChoice",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "OperatorObservationCommandOption",
                    "kind": "LinkedField",
                    "name": "observation",
                    "plural": false,
                    "selections": [
                      (v4/*:: as any*/),
                      (v5/*:: as any*/),
                      (v6/*:: as any*/),
                      (v7/*:: as any*/),
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
                      (v8/*:: as any*/),
                      (v9/*:: as any*/),
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
                          (v4/*:: as any*/),
                          (v5/*:: as any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "observedStatus",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "normalizedStatus",
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
                    "concreteType": "OperatorEvidenceCandidateCommandOption",
                    "kind": "LinkedField",
                    "name": "evidenceCandidate",
                    "plural": false,
                    "selections": [
                      (v4/*:: as any*/),
                      (v5/*:: as any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "workRunId",
                        "storageKey": null
                      },
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
                        "name": "sourceKind",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "sourceIdentity",
                        "storageKey": null
                      },
                      (v8/*:: as any*/),
                      (v9/*:: as any*/),
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
                    "plural": false,
                    "selections": [
                      (v4/*:: as any*/),
                      (v5/*:: as any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "evidenceCandidateId",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "result",
                        "storageKey": null
                      },
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
                    "plural": false,
                    "selections": [
                      (v4/*:: as any*/),
                      (v5/*:: as any*/),
                      (v6/*:: as any*/),
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
      (v2/*:: as any*/),
      (v3/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "OperatorRunCommandOptionPageQuery",
    "selections": (v10/*:: as any*/),
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
    "name": "OperatorRunCommandOptionPageQuery",
    "selections": (v10/*:: as any*/)
  },
  "params": {
    "cacheID": "991f009bbe70550b1449a1ea97023231",
    "id": null,
    "metadata": {},
    "name": "OperatorRunCommandOptionPageQuery",
    "operationKind": "query",
    "text": "query OperatorRunCommandOptionPageQuery(\n  $id: ID!\n  $kind: String!\n  $first: Int!\n  $after: String\n) {\n  operatorRunState(id: $id) {\n    commandOptionPage(kind: $kind, first: $first, after: $after) {\n      edges {\n        cursor\n        node {\n          observation {\n            key\n            label\n            runId\n            verificationCheckId\n            sourceGraphItemId\n            observationSourceKind\n            observationSourceIdentity\n            freshnessState\n            trustBasis\n            defaultOutcomeKey\n            outcomes {\n              key\n              label\n              observedStatus\n              normalizedStatus\n            }\n          }\n          evidenceCandidate {\n            key\n            label\n            workRunId\n            verificationCheckId\n            executionObservationId\n            sourceKind\n            sourceIdentity\n            freshnessState\n            trustBasis\n            sensitivity\n          }\n          evidenceAcceptance {\n            key\n            label\n            evidenceCandidateId\n            result\n            acceptancePolicyBasis\n          }\n          waiver {\n            key\n            label\n            runId\n            runRequiredCheckId\n            expectedExecutionState\n            expectedVerificationState\n            policyBasis\n          }\n        }\n      }\n      pageInfo {\n        hasNextPage\n        hasPreviousPage\n        startCursor\n        endCursor\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "dae94f2612540813b1c800c8b576f8ef";

export default node;
