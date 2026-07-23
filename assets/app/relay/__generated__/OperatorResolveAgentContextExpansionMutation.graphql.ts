/**
 * @generated SignedSource<<0979ccd0b932d2d16df4877b5626aca3>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type ResolveAgentContextExpansionInput = {
  contextExpansionRequestId: string;
  decision: string;
  expectedVersion: number;
  idempotencyKey: string;
  resolutionReason: string;
};
export type OperatorResolveAgentContextExpansionMutation$variables = {
  input: ResolveAgentContextExpansionInput;
};
export type OperatorResolveAgentContextExpansionMutation$data = {
  readonly resolveAgentContextExpansion: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly contextPackageId: string | null | undefined;
    readonly execution: {
      readonly currentStepKey: string | null | undefined;
      readonly id: string;
      readonly state: string;
      readonly stateVersion: number;
    };
    readonly operationId: string;
    readonly request: {
      readonly id: string;
      readonly state: string;
      readonly version: number;
    };
  };
};
export type OperatorResolveAgentContextExpansionMutation = {
  response: OperatorResolveAgentContextExpansionMutation$data;
  variables: OperatorResolveAgentContextExpansionMutation$variables;
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
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v3 = [
  {
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "input",
        "variableName": "input"
      }
    ],
    "concreteType": "ResolveAgentContextExpansionPayload",
    "kind": "LinkedField",
    "name": "resolveAgentContextExpansion",
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
        "concreteType": "OperatorCommandAgentRequest",
        "kind": "LinkedField",
        "name": "request",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          (v2/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "version",
            "storageKey": null
          }
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
          (v2/*:: as any*/),
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
    "name": "OperatorResolveAgentContextExpansionMutation",
    "selections": (v3/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorResolveAgentContextExpansionMutation",
    "selections": (v3/*:: as any*/)
  },
  "params": {
    "cacheID": "ec8a3e472c0476d26d4a8ea6de28735c",
    "id": null,
    "metadata": {},
    "name": "OperatorResolveAgentContextExpansionMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorResolveAgentContextExpansionMutation(\n  $input: ResolveAgentContextExpansionInput!\n) {\n  resolveAgentContextExpansion(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    request {\n      id\n      state\n      version\n    }\n    execution {\n      id\n      state\n      stateVersion\n      currentStepKey\n    }\n    contextPackageId\n  }\n}\n"
  }
};
})();

(node as any).hash = "1a6d2f39472f89b4c743282247b19195";

export default node;
