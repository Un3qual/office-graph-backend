/**
 * @generated SignedSource<<306dc7059f302445f37c5d482a7eb119>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type PacketsWorkspaceDetailQuery$variables = {
  id: string;
};
export type PacketsWorkspaceDetailQuery$data = {
  readonly operatorPacketWorkspace: {
    readonly allowedNextActions: ReadonlyArray<string>;
    readonly blockerReasons: ReadonlyArray<string>;
    readonly commandAffordances: ReadonlyArray<{
      readonly blockerReasons: ReadonlyArray<string>;
      readonly decisionLinks: ReadonlyArray<{
        readonly id: string;
        readonly type: string;
      }>;
      readonly identity: string;
      readonly inputDefaults: ReadonlyArray<{
        readonly field: string;
        readonly value: string | null | undefined;
        readonly values: ReadonlyArray<string>;
      }>;
      readonly reasonCodes: ReadonlyArray<string>;
      readonly requiredFields: ReadonlyArray<string>;
      readonly safeExplanation: string;
      readonly state: string;
      readonly targetIds: ReadonlyArray<{
        readonly id: string;
        readonly type: string;
      }>;
      readonly traceLinks: ReadonlyArray<{
        readonly id: string;
        readonly type: string;
      }>;
    }>;
    readonly currentVersion: {
      readonly autonomyPosture: string;
      readonly contextSummary: string;
      readonly id: string;
      readonly insertedAt: any;
      readonly lifecycleState: string;
      readonly objective: string;
      readonly operationId: string;
      readonly requirements: string;
      readonly sourceGraphItemIds: ReadonlyArray<string>;
      readonly successCriteria: string | null | undefined;
      readonly title: string;
      readonly verificationCheckIds: ReadonlyArray<string>;
      readonly versionNumber: number;
    };
    readonly packet: {
      readonly currentVersionId: string;
      readonly id: string;
      readonly operationId: string | null | undefined;
      readonly state: string;
      readonly title: string;
    };
    readonly ready: boolean;
    readonly sourceWatermark: string;
    readonly status: string;
    readonly versions: ReadonlyArray<{
      readonly autonomyPosture: string;
      readonly contextSummary: string;
      readonly id: string;
      readonly insertedAt: any;
      readonly lifecycleState: string;
      readonly objective: string;
      readonly operationId: string;
      readonly requirements: string;
      readonly sourceGraphItemIds: ReadonlyArray<string>;
      readonly successCriteria: string | null | undefined;
      readonly title: string;
      readonly verificationCheckIds: ReadonlyArray<string>;
      readonly versionNumber: number;
    }>;
  };
};
export type PacketsWorkspaceDetailQuery = {
  response: PacketsWorkspaceDetailQuery$data;
  variables: PacketsWorkspaceDetailQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "blockerReasons",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "operationId",
  "storageKey": null
},
v6 = [
  (v2/*:: as any*/),
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
  },
  (v3/*:: as any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "objective",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "contextSummary",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "requirements",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "successCriteria",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "autonomyPosture",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "sourceGraphItemIds",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "verificationCheckIds",
    "storageKey": null
  },
  (v5/*:: as any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "insertedAt",
    "storageKey": null
  }
],
v7 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "type",
    "storageKey": null
  },
  (v2/*:: as any*/)
],
v8 = [
  {
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "id",
        "variableName": "id"
      }
    ],
    "concreteType": "OperatorPacketWorkspace",
    "kind": "LinkedField",
    "name": "operatorPacketWorkspace",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "sourceWatermark",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "ready",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "status",
        "storageKey": null
      },
      (v1/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "allowedNextActions",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorPacketWorkspacePacket",
        "kind": "LinkedField",
        "name": "packet",
        "plural": false,
        "selections": [
          (v2/*:: as any*/),
          (v3/*:: as any*/),
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "currentVersionId",
            "storageKey": null
          },
          (v5/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorPacketWorkspaceVersion",
        "kind": "LinkedField",
        "name": "currentVersion",
        "plural": false,
        "selections": (v6/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorPacketWorkspaceVersion",
        "kind": "LinkedField",
        "name": "versions",
        "plural": true,
        "selections": (v6/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandAffordance",
        "kind": "LinkedField",
        "name": "commandAffordances",
        "plural": true,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "identity",
            "storageKey": null
          },
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "reasonCodes",
            "storageKey": null
          },
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "safeExplanation",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "requiredFields",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorCommandInputDefault",
            "kind": "LinkedField",
            "name": "inputDefaults",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "field",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "value",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "values",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorTypedId",
            "kind": "LinkedField",
            "name": "targetIds",
            "plural": true,
            "selections": (v7/*:: as any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorTypedId",
            "kind": "LinkedField",
            "name": "traceLinks",
            "plural": true,
            "selections": (v7/*:: as any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorTypedId",
            "kind": "LinkedField",
            "name": "decisionLinks",
            "plural": true,
            "selections": (v7/*:: as any*/),
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
    "name": "PacketsWorkspaceDetailQuery",
    "selections": (v8/*:: as any*/),
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "PacketsWorkspaceDetailQuery",
    "selections": (v8/*:: as any*/)
  },
  "params": {
    "cacheID": "ff9fbe7c77d1c71ddd8aa7ac2cc7494f",
    "id": null,
    "metadata": {},
    "name": "PacketsWorkspaceDetailQuery",
    "operationKind": "query",
    "text": "query PacketsWorkspaceDetailQuery(\n  $id: ID!\n) {\n  operatorPacketWorkspace(id: $id) {\n    sourceWatermark\n    ready\n    status\n    blockerReasons\n    allowedNextActions\n    packet {\n      id\n      title\n      state\n      currentVersionId\n      operationId\n    }\n    currentVersion {\n      id\n      versionNumber\n      lifecycleState\n      title\n      objective\n      contextSummary\n      requirements\n      successCriteria\n      autonomyPosture\n      sourceGraphItemIds\n      verificationCheckIds\n      operationId\n      insertedAt\n    }\n    versions {\n      id\n      versionNumber\n      lifecycleState\n      title\n      objective\n      contextSummary\n      requirements\n      successCriteria\n      autonomyPosture\n      sourceGraphItemIds\n      verificationCheckIds\n      operationId\n      insertedAt\n    }\n    commandAffordances {\n      identity\n      state\n      reasonCodes\n      blockerReasons\n      safeExplanation\n      requiredFields\n      inputDefaults {\n        field\n        value\n        values\n      }\n      targetIds {\n        type\n        id\n      }\n      traceLinks {\n        type\n        id\n      }\n      decisionLinks {\n        type\n        id\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "24d4484dbd67fa4b72867d8d0468deb7";

export default node;
