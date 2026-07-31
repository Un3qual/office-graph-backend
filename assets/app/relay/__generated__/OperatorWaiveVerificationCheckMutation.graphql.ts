/**
 * @generated SignedSource<<464f5a987aab8ddbdab22307bd505101>>
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
    } | null | undefined>;
    readonly command: string;
    readonly operationId: string;
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
        "concreteType": "WorkGraphVerificationResult",
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
    "cacheID": "109ac9fefd839ec90a3a9ce9814f9a2f",
    "id": null,
    "metadata": {},
    "name": "OperatorWaiveVerificationCheckMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorWaiveVerificationCheckMutation(\n  $input: WaiveVerificationCheckInput!\n) {\n  waiveVerificationCheck(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    verificationResult {\n      id\n      result\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "0c53d6fad02a37cac37634abedb40c07";

export default node;
