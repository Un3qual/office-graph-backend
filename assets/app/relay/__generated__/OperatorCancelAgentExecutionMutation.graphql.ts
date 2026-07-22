/**
 * @generated SignedSource<<ed63d31024634c6b89467f3eb7857b44>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type CancelAgentExecutionInput = {
  executionId: string;
  expectedStateVersion: number;
  idempotencyKey: string;
};
export type OperatorCancelAgentExecutionMutation$variables = {
  input: CancelAgentExecutionInput;
};
export type OperatorCancelAgentExecutionMutation$data = {
  readonly cancelAgentExecution: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly execution: {
      readonly currentStepKey: string | null | undefined;
      readonly id: string;
      readonly state: string;
      readonly stateVersion: number;
    };
    readonly operationId: string;
  };
};
export type OperatorCancelAgentExecutionMutation = {
  response: OperatorCancelAgentExecutionMutation$data;
  variables: OperatorCancelAgentExecutionMutation$variables;
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
    "concreteType": "CancelAgentExecutionPayload",
    "kind": "LinkedField",
    "name": "cancelAgentExecution",
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
        "concreteType": "OperatorCommandAgentExecution",
        "kind": "LinkedField",
        "name": "execution",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
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
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "currentStepKey",
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
    "name": "OperatorCancelAgentExecutionMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorCancelAgentExecutionMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "233bacbbf4405d65af483e9875d9788f",
    "id": null,
    "metadata": {},
    "name": "OperatorCancelAgentExecutionMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorCancelAgentExecutionMutation(\n  $input: CancelAgentExecutionInput!\n) {\n  cancelAgentExecution(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    execution {\n      id\n      state\n      stateVersion\n      currentStepKey\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "25f33b36b15076a30bdd7f2a8de9bebb";

export default node;
