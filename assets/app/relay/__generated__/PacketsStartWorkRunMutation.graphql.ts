/**
 * @generated SignedSource<<4bf4c0ac295af1e318ce4c389f507533>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type StartWorkRunInput = {
  authorityPosture: string;
  idempotencyKey: string;
  packetVersionId: string;
  reason: string;
  sourceSurface: string;
};
export type PacketsStartWorkRunMutation$variables = {
  input: StartWorkRunInput;
};
export type PacketsStartWorkRunMutation$data = {
  readonly startWorkRun: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly operationId: string;
    readonly requiredChecks: ReadonlyArray<{
      readonly id: string;
      readonly state: string;
      readonly verificationCheckId: string;
    }>;
    readonly run: {
      readonly executionState: string;
      readonly id: string;
      readonly verificationState: string;
    };
  };
};
export type PacketsStartWorkRunMutation = {
  response: PacketsStartWorkRunMutation$data;
  variables: PacketsStartWorkRunMutation$variables;
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
    "concreteType": "StartWorkRunPayload",
    "kind": "LinkedField",
    "name": "startWorkRun",
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
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandRunRequiredCheck",
        "kind": "LinkedField",
        "name": "requiredChecks",
        "plural": true,
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
    "name": "PacketsStartWorkRunMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "PacketsStartWorkRunMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "1fe52ed4c9204cb1cbbebaf00f59f3ec",
    "id": null,
    "metadata": {},
    "name": "PacketsStartWorkRunMutation",
    "operationKind": "mutation",
    "text": "mutation PacketsStartWorkRunMutation(\n  $input: StartWorkRunInput!\n) {\n  startWorkRun(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    run {\n      id\n      executionState\n      verificationState\n    }\n    requiredChecks {\n      id\n      verificationCheckId\n      state\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "0dd7d8770d755dc6e35f4a0997a73a53";

export default node;
