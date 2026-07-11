/**
 * @generated SignedSource<<95e18a06f142d23c398fb553cedce962>>
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
export type PacketsCreateWorkPacketMutation$variables = {
  input: CreateWorkPacketInput;
};
export type PacketsCreateWorkPacketMutation$data = {
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
export type PacketsCreateWorkPacketMutation = {
  response: PacketsCreateWorkPacketMutation$data;
  variables: PacketsCreateWorkPacketMutation$variables;
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
    "name": "PacketsCreateWorkPacketMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "PacketsCreateWorkPacketMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "e3afb1fb3908506cf268f2a0eee32877",
    "id": null,
    "metadata": {},
    "name": "PacketsCreateWorkPacketMutation",
    "operationKind": "mutation",
    "text": "mutation PacketsCreateWorkPacketMutation(\n  $input: CreateWorkPacketInput!\n) {\n  createWorkPacket(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    packet {\n      id\n      currentVersionId\n      title\n      state\n    }\n    packetVersion {\n      id\n      versionNumber\n      lifecycleState\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "cd1819abff64012a9f6148e9bebbba72";

export default node;
