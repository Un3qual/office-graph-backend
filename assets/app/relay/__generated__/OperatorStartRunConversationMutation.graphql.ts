/**
 * @generated SignedSource<<b5daca2c53f9f2b15a3228a1b5ed096f>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type StartRunConversationInput = {
  graphItemId: string;
  idempotencyKey: string;
  runId: string;
};
export type OperatorStartRunConversationMutation$variables = {
  input: StartRunConversationInput;
};
export type OperatorStartRunConversationMutation$data = {
  readonly startRunConversation: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly conversation: {
      readonly graphItemId: string;
      readonly id: string;
      readonly runId: string;
      readonly state: string;
      readonly stateVersion: number;
    };
    readonly operationId: string;
  };
};
export type OperatorStartRunConversationMutation = {
  response: OperatorStartRunConversationMutation$data;
  variables: OperatorStartRunConversationMutation$variables;
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
    "concreteType": "StartRunConversationPayload",
    "kind": "LinkedField",
    "name": "startRunConversation",
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
        "concreteType": "OperatorRunConversationRecord",
        "kind": "LinkedField",
        "name": "conversation",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "runId",
            "storageKey": null
          },
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
            "name": "state",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "stateVersion",
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
    "name": "OperatorStartRunConversationMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorStartRunConversationMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "271e68fa89db77fbb388081dd4ce14cc",
    "id": null,
    "metadata": {},
    "name": "OperatorStartRunConversationMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorStartRunConversationMutation(\n  $input: StartRunConversationInput!\n) {\n  startRunConversation(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    conversation {\n      id\n      runId\n      graphItemId\n      state\n      stateVersion\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "06a561e15cac7bf0dca6bfff09286423";

export default node;
