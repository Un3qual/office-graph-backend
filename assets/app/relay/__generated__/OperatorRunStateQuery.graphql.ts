/**
 * @generated SignedSource<<17a0d92d19cfcef32bb6e3516a41e13d>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorRunStateQuery$variables = {
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
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "type",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
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
  "name": "key",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "runId",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "freshnessState",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "trustBasis",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "workRunId",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "executionObservationId",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceKind",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceIdentity",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "result",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "policyBasis",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "graphItemId",
  "storageKey": null
},
v18 = [
  (v2/*:: as any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "status",
    "storageKey": null
  },
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
      (v3/*:: as any*/),
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
          (v2/*:: as any*/),
          (v4/*:: as any*/)
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
          (v5/*:: as any*/),
          (v6/*:: as any*/),
          (v7/*:: as any*/),
          (v8/*:: as any*/),
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
          (v9/*:: as any*/),
          (v10/*:: as any*/)
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
          (v5/*:: as any*/),
          (v6/*:: as any*/),
          (v11/*:: as any*/),
          (v8/*:: as any*/),
          (v12/*:: as any*/),
          (v13/*:: as any*/),
          (v14/*:: as any*/),
          (v9/*:: as any*/),
          (v10/*:: as any*/),
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
          (v5/*:: as any*/),
          (v6/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "evidenceCandidateId",
            "storageKey": null
          },
          (v15/*:: as any*/),
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
          (v5/*:: as any*/),
          (v6/*:: as any*/),
          (v7/*:: as any*/),
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
          (v16/*:: as any*/)
        ],
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
        "name": "title",
        "storageKey": null
      },
      (v3/*:: as any*/)
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
      (v17/*:: as any*/),
      (v8/*:: as any*/),
      (v3/*:: as any*/)
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
      (v4/*:: as any*/),
      (v8/*:: as any*/),
      (v17/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "normalizedStatus",
        "storageKey": null
      },
      (v9/*:: as any*/),
      (v10/*:: as any*/),
      (v13/*:: as any*/),
      (v14/*:: as any*/)
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
      (v8/*:: as any*/),
      (v12/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "claim",
        "storageKey": null
      },
      (v3/*:: as any*/),
      (v9/*:: as any*/),
      (v10/*:: as any*/),
      (v13/*:: as any*/),
      (v14/*:: as any*/)
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
      (v3/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "candidateId",
        "storageKey": null
      },
      (v11/*:: as any*/)
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
      (v15/*:: as any*/),
      (v8/*:: as any*/),
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
      (v16/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "targetGraphItemId",
        "storageKey": null
      },
      (v11/*:: as any*/),
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
      (v8/*:: as any*/),
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
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "OperatorRunStateQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*:: as any*/),
        "concreteType": "OperatorRunState",
        "kind": "LinkedField",
        "name": "operatorRunState",
        "plural": false,
        "selections": [
          {
            "kind": "InlineDataFragmentSpread",
            "name": "OperatorRunStateFragment",
            "selections": (v18/*:: as any*/),
            "args": null,
            "argumentDefinitions": []
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
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorRunStateQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*:: as any*/),
        "concreteType": "OperatorRunState",
        "kind": "LinkedField",
        "name": "operatorRunState",
        "plural": false,
        "selections": (v18/*:: as any*/),
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "791fdc902362895d28e8a39b664fbda2",
    "id": null,
    "metadata": {},
    "name": "OperatorRunStateQuery",
    "operationKind": "query",
    "text": "query OperatorRunStateQuery(\n  $id: ID!\n) {\n  operatorRunState(id: $id) {\n    ...OperatorRunStateFragment\n  }\n}\n\nfragment OperatorRunStateFragment on OperatorRunState {\n  type\n  status\n  allowedNextActions\n  commandAffordances {\n    identity\n    state\n    reasonCodes\n    blockerReasons\n    safeExplanation\n    requiredFields\n    inputDefaults {\n      field\n      value\n      values\n    }\n    targetIds {\n      type\n      id\n    }\n  }\n  commandOptions {\n    observation {\n      key\n      label\n      runId\n      verificationCheckId\n      sourceGraphItemId\n      observationSourceKind\n      observationSourceIdentity\n      freshnessState\n      trustBasis\n    }\n    evidenceCandidate {\n      key\n      label\n      workRunId\n      verificationCheckId\n      executionObservationId\n      sourceKind\n      sourceIdentity\n      freshnessState\n      trustBasis\n      sensitivity\n    }\n    evidenceAcceptance {\n      key\n      label\n      evidenceCandidateId\n      result\n      acceptancePolicyBasis\n    }\n    waiver {\n      key\n      label\n      runId\n      runRequiredCheckId\n      expectedExecutionState\n      expectedVerificationState\n      policyBasis\n    }\n  }\n  childSummary {\n    requiredChecks\n    observations\n    evidenceCandidates\n    evidenceItems\n    verificationResults\n    missingEvidence\n    hasMore\n  }\n  sourceWatermark\n  packet {\n    id\n    title\n    state\n  }\n  packetVersion {\n    id\n    versionNumber\n    lifecycleState\n    objective\n  }\n  run {\n    id\n    aggregateState\n    executionState\n    verificationState\n  }\n  requiredChecks {\n    id\n    graphItemId\n    verificationCheckId\n    state\n  }\n  observations {\n    id\n    verificationCheckId\n    graphItemId\n    normalizedStatus\n    freshnessState\n    trustBasis\n    sourceKind\n    sourceIdentity\n  }\n  evidenceCandidates {\n    id\n    verificationCheckId\n    executionObservationId\n    claim\n    state\n    freshnessState\n    trustBasis\n    sourceKind\n    sourceIdentity\n  }\n  evidenceItems {\n    id\n    state\n    candidateId\n    workRunId\n  }\n  verificationResults {\n    id\n    result\n    verificationCheckId\n    evidenceItemId\n    operationId\n    actorPrincipalId\n    policyBasis\n    targetGraphItemId\n    workRunId\n    workPacketVersionId\n  }\n  missingEvidence {\n    verificationCheckId\n    reason\n  }\n}\n"
  }
};
})();

(node as any).hash = "9c97302d65518a41573abde579cfeaa3";

export default node;
