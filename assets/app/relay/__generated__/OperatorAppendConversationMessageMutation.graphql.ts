/**
 * @generated SignedSource<<5f74db3baa02df231a510ea574303dde>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type AppendConversationMessageInput = {
  body: string;
  contributionKind: string;
  conversationId: string;
  domainActionOperationId?: string | null | undefined;
  idempotencyKey: string;
  proposedGraphChangeId?: string | null | undefined;
};
export type OperatorAppendConversationMessageMutation$variables = {
  input: AppendConversationMessageInput;
};
export type OperatorAppendConversationMessageMutation$data = {
  readonly appendConversationMessage: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly message: {
      readonly id: string;
    };
    readonly operationId: string;
  };
};
export type OperatorAppendConversationMessageMutation = {
  response: OperatorAppendConversationMessageMutation$data;
  variables: OperatorAppendConversationMessageMutation$variables;
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
    "concreteType": "AppendConversationMessagePayload",
    "kind": "LinkedField",
    "name": "appendConversationMessage",
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
        "concreteType": "OperatorRunConversationMessage",
        "kind": "LinkedField",
        "name": "message",
        "plural": false,
        "selections": [
          (v1/*:: as any*/)
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
    "name": "OperatorAppendConversationMessageMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorAppendConversationMessageMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "f57159a9f17ef2d3c3f55d34df98d2d1",
    "id": null,
    "metadata": {},
    "name": "OperatorAppendConversationMessageMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorAppendConversationMessageMutation(\n  $input: AppendConversationMessageInput!\n) {\n  appendConversationMessage(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    message {\n      id\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "604069cbd972c86abbd84cfda3fa4e43";

export default node;
