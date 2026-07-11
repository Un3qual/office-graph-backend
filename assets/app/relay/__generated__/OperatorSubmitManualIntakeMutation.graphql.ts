/**
 * @generated SignedSource<<c7279b48c636dc46b1d539660b93d47f>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type SubmitManualIntakeInput = {
  body: string;
  idempotencyKey: string;
  replayIdentity: string;
  sourceIdentity: string;
};
export type OperatorSubmitManualIntakeMutation$variables = {
  input: SubmitManualIntakeInput;
};
export type OperatorSubmitManualIntakeMutation$data = {
  readonly submitManualIntake: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly normalizedEventId: string;
    readonly operationId: string;
    readonly proposedChangeIds: ReadonlyArray<string>;
  };
};
export type OperatorSubmitManualIntakeMutation = {
  response: OperatorSubmitManualIntakeMutation$data;
  variables: OperatorSubmitManualIntakeMutation$variables;
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
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "input",
        "variableName": "input"
      }
    ],
    "concreteType": "SubmitManualIntakePayload",
    "kind": "LinkedField",
    "name": "submitManualIntake",
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
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "normalizedEventId",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "proposedChangeIds",
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
    "name": "OperatorSubmitManualIntakeMutation",
    "selections": (v1/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorSubmitManualIntakeMutation",
    "selections": (v1/*:: as any*/)
  },
  "params": {
    "cacheID": "8273bec27dd9c49bf2bd99b5e9c1a352",
    "id": null,
    "metadata": {},
    "name": "OperatorSubmitManualIntakeMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorSubmitManualIntakeMutation(\n  $input: SubmitManualIntakeInput!\n) {\n  submitManualIntake(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    normalizedEventId\n    proposedChangeIds\n  }\n}\n"
  }
};
})();

(node as any).hash = "449fa00bf81e935a168fd23b60533dba";

export default node;
