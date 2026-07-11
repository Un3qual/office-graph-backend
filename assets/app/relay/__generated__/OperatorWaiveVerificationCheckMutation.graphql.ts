/**
 * @generated SignedSource<<565928ad60371b65820c085c57565d51>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type WaiveVerificationCheckInput = {
  expectedExecutionState: string;
  expectedVerificationState: string;
  idempotencyKey: string;
  policyBasis: string;
  reason: string;
  runId: string;
  runRequiredCheckId: string;
};
export type OperatorWaiveVerificationCheckMutation$variables = {
  input: WaiveVerificationCheckInput;
};
export type OperatorWaiveVerificationCheckMutation$data = {
  readonly waiveVerificationCheck: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly operationId: string;
    readonly requiredCheck: {
      readonly id: string;
      readonly state: string;
      readonly verificationCheckId: string;
    };
    readonly run: {
      readonly executionState: string;
      readonly id: string;
      readonly verificationState: string;
    };
    readonly verificationResult: {
      readonly id: string;
      readonly result: string;
    };
  };
};
export type OperatorWaiveVerificationCheckMutation = {
  response: OperatorWaiveVerificationCheckMutation$data;
  variables: OperatorWaiveVerificationCheckMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "input"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v2 = [
  {
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "input",
        "variableName": "input"
      }
    ],
    "concreteType": "WaiveVerificationCheckPayload",
    "kind": "LinkedField",
    "name": "waiveVerificationCheck",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "command",
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
        "concreteType": "OperatorTypedId",
        "kind": "LinkedField",
        "name": "affectedIds",
        "plural": true,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "type",
            "storageKey": null
          },
          (v1/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandVerificationResult",
        "kind": "LinkedField",
        "name": "verificationResult",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "result",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandRunRequiredCheck",
        "kind": "LinkedField",
        "name": "requiredCheck",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "verificationCheckId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "state",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandWorkRun",
        "kind": "LinkedField",
        "name": "run",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
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
    "name": "OperatorWaiveVerificationCheckMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorWaiveVerificationCheckMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "c365528b4ef8a3a4c9183271cafdaa30",
    "id": null,
    "metadata": {},
    "name": "OperatorWaiveVerificationCheckMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorWaiveVerificationCheckMutation(\n  $input: WaiveVerificationCheckInput!\n) {\n  waiveVerificationCheck(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    verificationResult {\n      id\n      result\n    }\n    requiredCheck {\n      id\n      verificationCheckId\n      state\n    }\n    run {\n      id\n      executionState\n      verificationState\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "138504c4919902d6eec0146e5f75540a";

export default node;
