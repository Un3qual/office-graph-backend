/**
 * @generated SignedSource<<63d3bb081cfc0a1a4693e4e1207816e9>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type InvokeAgentInput = {
  autonomyMode: string;
  bindingId: string;
  graphItemId: string;
  idempotencyKey: string;
  requestedCapabilities: ReadonlyArray<string>;
  requestedOutcome: string;
  runId: string;
};
export type OperatorInvokeAgentMutation$variables = {
  input: InvokeAgentInput;
};
export type OperatorInvokeAgentMutation$data = {
  readonly invokeAgent: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly contextPackageId: string;
    readonly execution: {
      readonly currentStepKey: string | null | undefined;
      readonly id: string;
      readonly state: string;
      readonly stateVersion: number;
    };
    readonly operationId: string;
  };
};
export type OperatorInvokeAgentMutation = {
  response: OperatorInvokeAgentMutation$data;
  variables: OperatorInvokeAgentMutation$variables;
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
    "concreteType": "InvokeAgentPayload",
    "kind": "LinkedField",
    "name": "invokeAgent",
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
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "contextPackageId",
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
    "name": "OperatorInvokeAgentMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorInvokeAgentMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "c168718de14fc76d0f1a8e0172b16471",
    "id": null,
    "metadata": {},
    "name": "OperatorInvokeAgentMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorInvokeAgentMutation(\n  $input: InvokeAgentInput!\n) {\n  invokeAgent(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    execution {\n      id\n      state\n      stateVersion\n      currentStepKey\n    }\n    contextPackageId\n  }\n}\n"
  }
};
})();

(node as any).hash = "096e05f3bf67f3f64d6dd8a24587c467";

export default node;
