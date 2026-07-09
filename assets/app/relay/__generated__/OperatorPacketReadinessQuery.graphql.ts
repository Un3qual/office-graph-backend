/**
 * @generated SignedSource<<8febed4e0b19bd115ff5bbf206ee2cf0>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type OperatorPacketReadinessInput = {
  autonomyPosture?: string | null | undefined;
  contextSummary?: string | null | undefined;
  objective?: string | null | undefined;
  requirements?: string | null | undefined;
  sourceGraphItemIds?: ReadonlyArray<string> | null | undefined;
  successCriteria?: string | null | undefined;
  title?: string | null | undefined;
  verificationCheckIds?: ReadonlyArray<string> | null | undefined;
};
export type OperatorPacketReadinessQuery$variables = {
  input: OperatorPacketReadinessInput;
};
export type OperatorPacketReadinessQuery$data = {
  readonly operatorPacketReadiness: {
    readonly " $fragmentSpreads": FragmentRefs<"OperatorPacketReadinessFragment">;
  };
};
export type OperatorPacketReadinessQuery = {
  response: OperatorPacketReadinessQuery$data;
  variables: OperatorPacketReadinessQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "input"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
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
  "name": "ready",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "status",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "allowedNextActions",
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
  "name": "blockerReasons",
  "storageKey": null
},
v8 = {
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
    (v7/*:: as any*/),
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
    }
  ],
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sourceWatermark",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "OperatorPacketReadinessQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*:: as any*/),
        "concreteType": "OperatorPacketReadiness",
        "kind": "LinkedField",
        "name": "operatorPacketReadiness",
        "plural": false,
        "selections": [
          {
            "kind": "InlineDataFragmentSpread",
            "name": "OperatorPacketReadinessFragment",
            "selections": [
              (v2/*:: as any*/),
              (v3/*:: as any*/),
              (v4/*:: as any*/),
              (v5/*:: as any*/),
              (v8/*:: as any*/),
              (v7/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorSourceLink",
                "kind": "LinkedField",
                "name": "sourceLinks",
                "plural": true,
                "selections": [
                  (v9/*:: as any*/)
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
                  (v6/*:: as any*/)
                ],
                "storageKey": null
              },
              (v10/*:: as any*/)
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
    "name": "OperatorPacketReadinessQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*:: as any*/),
        "concreteType": "OperatorPacketReadiness",
        "kind": "LinkedField",
        "name": "operatorPacketReadiness",
        "plural": false,
        "selections": [
          (v2/*:: as any*/),
          (v3/*:: as any*/),
          (v4/*:: as any*/),
          (v5/*:: as any*/),
          (v8/*:: as any*/),
          (v7/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorSourceLink",
            "kind": "LinkedField",
            "name": "sourceLinks",
            "plural": true,
            "selections": [
              (v9/*:: as any*/),
              (v11/*:: as any*/)
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
              (v6/*:: as any*/),
              (v11/*:: as any*/)
            ],
            "storageKey": null
          },
          (v10/*:: as any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "7f5a2e3dfdda740b4f3b2871be10aec9",
    "id": null,
    "metadata": {},
    "name": "OperatorPacketReadinessQuery",
    "operationKind": "query",
    "text": "query OperatorPacketReadinessQuery(\n  $input: OperatorPacketReadinessInput!\n) {\n  operatorPacketReadiness(input: $input) {\n    ...OperatorPacketReadinessFragment\n  }\n}\n\nfragment OperatorPacketReadinessFragment on OperatorPacketReadiness {\n  type\n  ready\n  status\n  allowedNextActions\n  commandAffordances {\n    identity\n    state\n    reasonCodes\n    blockerReasons\n    safeExplanation\n    requiredFields\n  }\n  blockerReasons\n  sourceLinks {\n    title\n    id\n  }\n  requiredChecks {\n    state\n    id\n  }\n  sourceWatermark\n}\n"
  }
};
})();

(node as any).hash = "d552c829fbd0b1118ee66d76c9396a94";

export default node;
