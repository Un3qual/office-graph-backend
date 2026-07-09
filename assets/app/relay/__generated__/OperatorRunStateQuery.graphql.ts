/**
 * @generated SignedSource<<96d9f9b3ef5286cec882536e5c3f4936>>
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
  "name": "status",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "allowedNextActions",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v6 = {
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
    (v5/*:: as any*/),
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
    }
  ],
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceWatermark",
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
  "concreteType": "OperatorPacketRef",
  "kind": "LinkedField",
  "name": "packet",
  "plural": false,
  "selections": [
    (v8/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "title",
      "storageKey": null
    },
    (v5/*:: as any*/)
  ],
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorPacketVersionRef",
  "kind": "LinkedField",
  "name": "packetVersion",
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
v11 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorRunRef",
  "kind": "LinkedField",
  "name": "run",
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
    }
  ],
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
  "name": "sourceKind",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceIdentity",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorObservation",
  "kind": "LinkedField",
  "name": "observations",
  "plural": true,
  "selections": [
    (v8/*:: as any*/),
    (v12/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "graphItemId",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "normalizedStatus",
      "storageKey": null
    },
    (v13/*:: as any*/),
    (v14/*:: as any*/),
    (v15/*:: as any*/),
    (v16/*:: as any*/)
  ],
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorEvidenceCandidate",
  "kind": "LinkedField",
  "name": "evidenceCandidates",
  "plural": true,
  "selections": [
    (v8/*:: as any*/),
    (v12/*:: as any*/),
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
    (v5/*:: as any*/),
    (v13/*:: as any*/),
    (v14/*:: as any*/),
    (v15/*:: as any*/),
    (v16/*:: as any*/)
  ],
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "workRunId",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorEvidenceItem",
  "kind": "LinkedField",
  "name": "evidenceItems",
  "plural": true,
  "selections": [
    (v8/*:: as any*/),
    (v5/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "candidateId",
      "storageKey": null
    },
    (v19/*:: as any*/)
  ],
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "concreteType": "OperatorVerificationResult",
  "kind": "LinkedField",
  "name": "verificationResults",
  "plural": true,
  "selections": [
    (v8/*:: as any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "result",
      "storageKey": null
    },
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
    (v19/*:: as any*/),
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
v22 = {
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
};
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
            "selections": [
              (v2/*:: as any*/),
              (v3/*:: as any*/),
              (v4/*:: as any*/),
              (v6/*:: as any*/),
              (v7/*:: as any*/),
              (v9/*:: as any*/),
              (v10/*:: as any*/),
              (v11/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorRequiredCheck",
                "kind": "LinkedField",
                "name": "requiredChecks",
                "plural": true,
                "selections": [
                  (v12/*:: as any*/),
                  (v5/*:: as any*/)
                ],
                "storageKey": null
              },
              (v17/*:: as any*/),
              (v18/*:: as any*/),
              (v20/*:: as any*/),
              (v21/*:: as any*/),
              (v22/*:: as any*/)
            ],
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
        "selections": [
          (v2/*:: as any*/),
          (v3/*:: as any*/),
          (v4/*:: as any*/),
          (v6/*:: as any*/),
          (v7/*:: as any*/),
          (v9/*:: as any*/),
          (v10/*:: as any*/),
          (v11/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorRequiredCheck",
            "kind": "LinkedField",
            "name": "requiredChecks",
            "plural": true,
            "selections": [
              (v12/*:: as any*/),
              (v5/*:: as any*/),
              (v8/*:: as any*/)
            ],
            "storageKey": null
          },
          (v17/*:: as any*/),
          (v18/*:: as any*/),
          (v20/*:: as any*/),
          (v21/*:: as any*/),
          (v22/*:: as any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "247d465d94f600ef736875b0595f8cbe",
    "id": null,
    "metadata": {},
    "name": "OperatorRunStateQuery",
    "operationKind": "query",
    "text": "query OperatorRunStateQuery(\n  $id: ID!\n) {\n  operatorRunState(id: $id) {\n    ...OperatorRunStateFragment\n  }\n}\n\nfragment OperatorRunStateFragment on OperatorRunState {\n  type\n  status\n  allowedNextActions\n  commandAffordances {\n    identity\n    state\n    reasonCodes\n    blockerReasons\n    safeExplanation\n    requiredFields\n    inputDefaults {\n      field\n      value\n      values\n    }\n  }\n  sourceWatermark\n  packet {\n    id\n    title\n    state\n  }\n  packetVersion {\n    id\n    versionNumber\n    lifecycleState\n    objective\n  }\n  run {\n    id\n    aggregateState\n    executionState\n    verificationState\n  }\n  requiredChecks {\n    verificationCheckId\n    state\n    id\n  }\n  observations {\n    id\n    verificationCheckId\n    graphItemId\n    normalizedStatus\n    freshnessState\n    trustBasis\n    sourceKind\n    sourceIdentity\n  }\n  evidenceCandidates {\n    id\n    verificationCheckId\n    executionObservationId\n    claim\n    state\n    freshnessState\n    trustBasis\n    sourceKind\n    sourceIdentity\n  }\n  evidenceItems {\n    id\n    state\n    candidateId\n    workRunId\n  }\n  verificationResults {\n    id\n    result\n    verificationCheckId\n    evidenceItemId\n    operationId\n    actorPrincipalId\n    policyBasis\n    targetGraphItemId\n    workRunId\n    workPacketVersionId\n  }\n  missingEvidence {\n    verificationCheckId\n    reason\n  }\n}\n"
  }
};
})();

(node as any).hash = "9c97302d65518a41573abde579cfeaa3";

export default node;
