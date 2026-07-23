/**
 * @generated SignedSource<<36eb920444f1267cde1a61cc5472c108>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type ResolveAgentApprovalInput = {
  approvalRequestId: string;
  decision: string;
  expectedVersion: number;
  idempotencyKey: string;
  resolutionReason: string;
};
export type OperatorResolveAgentApprovalMutation$variables = {
  input: ResolveAgentApprovalInput;
};
export type OperatorResolveAgentApprovalMutation$data = {
  readonly resolveAgentApproval: {
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
    readonly request: {
      readonly id: string;
      readonly state: string;
      readonly version: number;
    };
  };
};
export type OperatorResolveAgentApprovalMutation = {
  response: OperatorResolveAgentApprovalMutation$data;
  variables: OperatorResolveAgentApprovalMutation$variables;
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
    "concreteType": "ResolveAgentApprovalPayload",
    "kind": "LinkedField",
    "name": "resolveAgentApproval",
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
    "name": "OperatorResolveAgentApprovalMutation",
    "selections": (v3/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorResolveAgentApprovalMutation",
    "selections": (v3/*:: as any*/)
  },
  "params": {
    "cacheID": "839fa43f8491ca0c5e3e8d8dae671cc6",
    "id": null,
    "metadata": {},
    "name": "OperatorResolveAgentApprovalMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorResolveAgentApprovalMutation(\n  $input: ResolveAgentApprovalInput!\n) {\n  resolveAgentApproval(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    request {\n      id\n      state\n      version\n    }\n    execution {\n      id\n      state\n      stateVersion\n      currentStepKey\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "57a9ac8a421e7d13637103622ecfbc35";

export default node;
