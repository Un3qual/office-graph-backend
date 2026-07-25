/**
 * @generated SignedSource<<66ee22a0af41dbc18526f9bb228b5bc9>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorRunCommandOptionPageQuery$variables = {
  evidenceAcceptanceAfter?: string | null | undefined;
  evidenceCandidateAfter?: string | null | undefined;
  first: number;
  id: string;
  loadEvidenceAcceptance: boolean;
  loadEvidenceCandidate: boolean;
  loadObservation: boolean;
  loadWaiver: boolean;
  observationAfter?: string | null | undefined;
  waiverAfter?: string | null | undefined;
};
export type OperatorRunCommandOptionPageQuery$data = {
  readonly evidenceAcceptance?: {
    readonly " $fragmentSpreads": FragmentRefs<"OperatorRunCommandOptionPageConnectionFragment">;
  } | null | undefined;
  readonly evidenceCandidate?: {
    readonly " $fragmentSpreads": FragmentRefs<"OperatorRunCommandOptionPageConnectionFragment">;
  } | null | undefined;
  readonly observation?: {
    readonly " $fragmentSpreads": FragmentRefs<"OperatorRunCommandOptionPageConnectionFragment">;
  } | null | undefined;
  readonly waiver?: {
    readonly " $fragmentSpreads": FragmentRefs<"OperatorRunCommandOptionPageConnectionFragment">;
  } | null | undefined;
};
export type OperatorRunCommandOptionPageQuery = {
  response: OperatorRunCommandOptionPageQuery$data;
  variables: OperatorRunCommandOptionPageQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "evidenceAcceptanceAfter"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "evidenceCandidateAfter"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "loadEvidenceAcceptance"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "loadEvidenceCandidate"
},
v6 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "loadObservation"
},
v7 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "loadWaiver"
},
v8 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "observationAfter"
},
v9 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "waiverAfter"
},
v10 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v11 = {
  "kind": "Variable",
  "name": "id",
  "variableName": "id"
},
v12 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "observationAfter"
  },
  (v10/*:: as any*/),
  (v11/*:: as any*/),
  {
    "kind": "Literal",
    "name": "kind",
    "value": "observation"
  }
],
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "key",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "runId",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "freshnessState",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "trustBasis",
  "storageKey": null
},
v19 = [
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
              (v13/*:: as any*/),
              (v14/*:: as any*/),
              (v15/*:: as any*/),
              (v16/*:: as any*/),
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
              (v17/*:: as any*/),
              (v18/*:: as any*/),
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
                  (v13/*:: as any*/),
                  (v14/*:: as any*/),
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
              (v13/*:: as any*/),
              (v14/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "workRunId",
                "storageKey": null
              },
              (v16/*:: as any*/),
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
              (v17/*:: as any*/),
              (v18/*:: as any*/),
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
              (v13/*:: as any*/),
              (v14/*:: as any*/),
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
              (v13/*:: as any*/),
              (v14/*:: as any*/),
              (v15/*:: as any*/),
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
v20 = [
  {
    "kind": "InlineDataFragmentSpread",
    "name": "OperatorRunCommandOptionPageConnectionFragment",
    "selections": (v19/*:: as any*/),
    "args": null,
    "argumentDefinitions": ([]/*:: as any*/)
  }
],
v21 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "evidenceCandidateAfter"
  },
  (v10/*:: as any*/),
  (v11/*:: as any*/),
  {
    "kind": "Literal",
    "name": "kind",
    "value": "evidence_candidate"
  }
],
v22 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "evidenceAcceptanceAfter"
  },
  (v10/*:: as any*/),
  (v11/*:: as any*/),
  {
    "kind": "Literal",
    "name": "kind",
    "value": "evidence_acceptance"
  }
],
v23 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "waiverAfter"
  },
  (v10/*:: as any*/),
  (v11/*:: as any*/),
  {
    "kind": "Literal",
    "name": "kind",
    "value": "waiver"
  }
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/),
      (v2/*:: as any*/),
      (v3/*:: as any*/),
      (v4/*:: as any*/),
      (v5/*:: as any*/),
      (v6/*:: as any*/),
      (v7/*:: as any*/),
      (v8/*:: as any*/),
      (v9/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": {
      "throwOnFieldError": true
    },
    "name": "OperatorRunCommandOptionPageQuery",
    "selections": [
      {
        "condition": "loadObservation",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "observation",
            "args": (v12/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v20/*:: as any*/),
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadEvidenceCandidate",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "evidenceCandidate",
            "args": (v21/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v20/*:: as any*/),
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadEvidenceAcceptance",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "evidenceAcceptance",
            "args": (v22/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v20/*:: as any*/),
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadWaiver",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "waiver",
            "args": (v23/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v20/*:: as any*/),
            "storageKey": null
          }
        ]
      }
    ],
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v3/*:: as any*/),
      (v2/*:: as any*/),
      (v8/*:: as any*/),
      (v1/*:: as any*/),
      (v0/*:: as any*/),
      (v9/*:: as any*/),
      (v6/*:: as any*/),
      (v5/*:: as any*/),
      (v4/*:: as any*/),
      (v7/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "OperatorRunCommandOptionPageQuery",
    "selections": [
      {
        "condition": "loadObservation",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "observation",
            "args": (v12/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v19/*:: as any*/),
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadEvidenceCandidate",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "evidenceCandidate",
            "args": (v21/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v19/*:: as any*/),
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadEvidenceAcceptance",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "evidenceAcceptance",
            "args": (v22/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v19/*:: as any*/),
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadWaiver",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "waiver",
            "args": (v23/*:: as any*/),
            "concreteType": "OperatorRunCommandOptionChoiceConnection",
            "kind": "LinkedField",
            "name": "operatorRunCommandOptionPage",
            "plural": false,
            "selections": (v19/*:: as any*/),
            "storageKey": null
          }
        ]
      }
    ]
  },
  "params": {
    "cacheID": "0cc5e0c78002ddeb8bc9c5693a4351c4",
    "id": null,
    "metadata": {},
    "name": "OperatorRunCommandOptionPageQuery",
    "operationKind": "query",
    "text": "query OperatorRunCommandOptionPageQuery(\n  $id: ID!\n  $first: Int!\n  $observationAfter: String\n  $evidenceCandidateAfter: String\n  $evidenceAcceptanceAfter: String\n  $waiverAfter: String\n  $loadObservation: Boolean!\n  $loadEvidenceCandidate: Boolean!\n  $loadEvidenceAcceptance: Boolean!\n  $loadWaiver: Boolean!\n) {\n  observation: operatorRunCommandOptionPage(id: $id, kind: \"observation\", first: $first, after: $observationAfter) @include(if: $loadObservation) {\n    ...OperatorRunCommandOptionPageConnectionFragment\n  }\n  evidenceCandidate: operatorRunCommandOptionPage(id: $id, kind: \"evidence_candidate\", first: $first, after: $evidenceCandidateAfter) @include(if: $loadEvidenceCandidate) {\n    ...OperatorRunCommandOptionPageConnectionFragment\n  }\n  evidenceAcceptance: operatorRunCommandOptionPage(id: $id, kind: \"evidence_acceptance\", first: $first, after: $evidenceAcceptanceAfter) @include(if: $loadEvidenceAcceptance) {\n    ...OperatorRunCommandOptionPageConnectionFragment\n  }\n  waiver: operatorRunCommandOptionPage(id: $id, kind: \"waiver\", first: $first, after: $waiverAfter) @include(if: $loadWaiver) {\n    ...OperatorRunCommandOptionPageConnectionFragment\n  }\n}\n\nfragment OperatorRunCommandOptionPageConnectionFragment on OperatorRunCommandOptionChoiceConnection {\n  edges {\n    cursor\n    node {\n      observation {\n        key\n        label\n        runId\n        verificationCheckId\n        sourceGraphItemId\n        observationSourceKind\n        observationSourceIdentity\n        freshnessState\n        trustBasis\n        defaultOutcomeKey\n        outcomes {\n          key\n          label\n          observedStatus\n          normalizedStatus\n        }\n      }\n      evidenceCandidate {\n        key\n        label\n        workRunId\n        verificationCheckId\n        executionObservationId\n        sourceKind\n        sourceIdentity\n        freshnessState\n        trustBasis\n        sensitivity\n      }\n      evidenceAcceptance {\n        key\n        label\n        evidenceCandidateId\n        result\n        acceptancePolicyBasis\n      }\n      waiver {\n        key\n        label\n        runId\n        runRequiredCheckId\n        expectedExecutionState\n        expectedVerificationState\n        policyBasis\n      }\n    }\n  }\n  pageInfo {\n    hasNextPage\n    hasPreviousPage\n    startCursor\n    endCursor\n  }\n}\n"
  }
};
})();

(node as any).hash = "8d6126750417eace1b4168a7d920e370";

export default node;
