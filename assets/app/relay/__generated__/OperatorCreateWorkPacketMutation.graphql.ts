/**
 * @generated SignedSource<<b1fa1978ba91246db1bea9fea0a0abc1>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type CreateWorkPacketInput = {
  autonomyPosture: string;
  contextSummary: string;
  idempotencyKey: string;
  objective: string;
  requirements: string;
  sourceGraphItemIds: ReadonlyArray<string>;
  successCriteria: string;
  title: string;
  verificationCheckIds: ReadonlyArray<string>;
};
export type OperatorCreateWorkPacketMutation$variables = {
  input: CreateWorkPacketInput;
};
export type OperatorCreateWorkPacketMutation$data = {
  readonly createWorkPacket: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly operationId: string;
    readonly packet: {
      readonly currentVersionId: string;
      readonly id: string;
      readonly state: string;
      readonly title: string;
    };
    readonly packetVersion: {
      readonly id: string;
      readonly lifecycleState: string;
      readonly versionNumber: number;
    };
  };
};
export type OperatorCreateWorkPacketMutation = {
  response: OperatorCreateWorkPacketMutation$data;
  variables: OperatorCreateWorkPacketMutation$variables;
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
    "concreteType": "CreateWorkPacketPayload",
    "kind": "LinkedField",
    "name": "createWorkPacket",
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
        "concreteType": "OperatorCommandWorkPacket",
        "kind": "LinkedField",
        "name": "packet",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "currentVersionId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "title",
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
        "concreteType": "OperatorCommandWorkPacketVersion",
        "kind": "LinkedField",
        "name": "packetVersion",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "versionNumber",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "lifecycleState",
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
    "name": "OperatorCreateWorkPacketMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorCreateWorkPacketMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "41af3e14e288810d2cd9131b86b11a1f",
    "id": null,
    "metadata": {},
    "name": "OperatorCreateWorkPacketMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorCreateWorkPacketMutation(\n  $input: CreateWorkPacketInput!\n) {\n  createWorkPacket(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    packet {\n      id\n      currentVersionId\n      title\n      state\n    }\n    packetVersion {\n      id\n      versionNumber\n      lifecycleState\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "794696a70bb3a5a7d28b38a6698c1337";

export default node;
