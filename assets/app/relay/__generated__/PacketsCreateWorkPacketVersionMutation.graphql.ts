/**
 * @generated SignedSource<<2a91db47c566b2a075ccd7d0793508c8>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type CreateWorkPacketVersionInput = {
  autonomyPosture: string;
  contextSummary: string;
  expectedCurrentVersionId: string;
  idempotencyKey: string;
  objective: string;
  packetId: string;
  requirements: string;
  sourceGraphItemIds: ReadonlyArray<string>;
  successCriteria: string;
  title: string;
  verificationCheckIds: ReadonlyArray<string>;
};
export type PacketsCreateWorkPacketVersionMutation$variables = {
  input: CreateWorkPacketVersionInput;
};
export type PacketsCreateWorkPacketVersionMutation$data = {
  readonly createWorkPacketVersion: {
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
export type PacketsCreateWorkPacketVersionMutation = {
  response: PacketsCreateWorkPacketVersionMutation$data;
  variables: PacketsCreateWorkPacketVersionMutation$variables;
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
    "concreteType": "CreateWorkPacketVersionPayload",
    "kind": "LinkedField",
    "name": "createWorkPacketVersion",
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
    "name": "PacketsCreateWorkPacketVersionMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "PacketsCreateWorkPacketVersionMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "a3aa86fda2eae6099a572dc1de8c09aa",
    "id": null,
    "metadata": {},
    "name": "PacketsCreateWorkPacketVersionMutation",
    "operationKind": "mutation",
    "text": "mutation PacketsCreateWorkPacketVersionMutation(\n  $input: CreateWorkPacketVersionInput!\n) {\n  createWorkPacketVersion(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    packet {\n      id\n      currentVersionId\n      title\n      state\n    }\n    packetVersion {\n      id\n      versionNumber\n      lifecycleState\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "a3fca99b2e9ca29424c57c79618c4733";

export default node;
