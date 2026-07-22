/**
 * @generated SignedSource<<8bc866dd4b4302bb3aa089eb3dd6aec6>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type OperatorRunConversationQuery$variables = {
  graphItemId: string;
  runId: string;
};
export type OperatorRunConversationQuery$data = {
  readonly operatorRunConversation: {
    readonly allowedNextActions: ReadonlyArray<string>;
    readonly approvalRequests: ReadonlyArray<{
      readonly capabilityKey: string | null | undefined;
      readonly executionId: string;
      readonly expiresAt: string;
      readonly externalWrite: boolean;
      readonly id: string;
      readonly reason: string;
      readonly requestedAction: string;
      readonly resolutionReason: string | null | undefined;
      readonly scopeId: string;
      readonly scopeType: string;
      readonly sensitivity: string;
      readonly state: string;
      readonly stepKey: string;
      readonly version: number;
    }>;
    readonly commandAffordances: ReadonlyArray<{
      readonly blockerReasons: ReadonlyArray<string>;
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
    }>;
    readonly contextExpansionRequests: ReadonlyArray<{
      readonly accessMode: string;
      readonly capabilityKey: string | null | undefined;
      readonly executionId: string;
      readonly expectedDurationSeconds: number;
      readonly expiresAt: string;
      readonly id: string;
      readonly reason: string;
      readonly resolutionReason: string | null | undefined;
      readonly sensitivity: string;
      readonly state: string;
      readonly stepKey: string;
      readonly targetResourceId: string;
      readonly targetResourceType: string;
      readonly targetScopeId: string;
      readonly targetScopeType: string;
      readonly version: number;
    }>;
    readonly conversation: {
      readonly graphItemId: string;
      readonly id: string;
      readonly runId: string;
      readonly state: string;
      readonly stateVersion: number;
    } | null | undefined;
    readonly executions: ReadonlyArray<{
      readonly attemptCount: number;
      readonly autonomyMode: string;
      readonly bindingId: string;
      readonly currentStepKey: string | null | undefined;
      readonly failureCode: string | null | undefined;
      readonly id: string;
      readonly insertedAt: string;
      readonly invocationMode: string;
      readonly origin: string;
      readonly requestedOutcome: string;
      readonly state: string;
      readonly stateVersion: number;
      readonly updatedAt: string;
    }>;
    readonly messages: ReadonlyArray<{
      readonly body: string;
      readonly executionId: string | null | undefined;
      readonly id: string;
      readonly insertedAt: string;
      readonly referencedContext: {
        readonly entries: ReadonlyArray<{
          readonly posture: string;
          readonly rationaleCode: string;
        }>;
        readonly packageId: string | null | undefined;
        readonly version: number | null | undefined;
        readonly visibility: string;
      } | null | undefined;
      readonly source: string;
    }>;
    readonly sourceWatermark: string;
    readonly type: string;
  };
};
export type OperatorRunConversationQuery = {
  response: OperatorRunConversationQuery$data;
  variables: OperatorRunConversationQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "graphItemId"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "runId"
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "type",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stateVersion",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "executionId",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "insertedAt",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "version",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stepKey",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "reason",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "capabilityKey",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sensitivity",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "expiresAt",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resolutionReason",
  "storageKey": null
},
v15 = [
  {
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "graphItemId",
        "variableName": "graphItemId"
      },
      {
        "kind": "Variable",
        "name": "runId",
        "variableName": "runId"
      }
    ],
    "concreteType": "OperatorRunConversation",
    "kind": "LinkedField",
    "name": "operatorRunConversation",
    "plural": false,
    "selections": [
      (v2/*:: as any*/),
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
        "name": "allowedNextActions",
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
          (v3/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "reasonCodes",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "blockerReasons",
            "storageKey": null
          },
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
            "selections": [
              (v2/*:: as any*/),
              (v4/*:: as any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorRunConversationRecord",
        "kind": "LinkedField",
        "name": "conversation",
        "plural": false,
        "selections": [
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "runId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "graphItemId",
            "storageKey": null
          },
          (v3/*:: as any*/),
          (v5/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorRunConversationMessage",
        "kind": "LinkedField",
        "name": "messages",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "source",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "body",
            "storageKey": null
          },
          (v6/*:: as any*/),
          (v7/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "OperatorRunConversationReferencedContext",
            "kind": "LinkedField",
            "name": "referencedContext",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "visibility",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "packageId",
                "storageKey": null
              },
              (v8/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "OperatorRunConversationContextEntry",
                "kind": "LinkedField",
                "name": "entries",
                "plural": true,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "posture",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "rationaleCode",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorRunConversationExecution",
        "kind": "LinkedField",
        "name": "executions",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "bindingId",
            "storageKey": null
          },
          (v3/*:: as any*/),
          (v5/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "currentStepKey",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "attemptCount",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "failureCode",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "requestedOutcome",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "invocationMode",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "origin",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "autonomyMode",
            "storageKey": null
          },
          (v7/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "updatedAt",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorRunConversationApprovalRequest",
        "kind": "LinkedField",
        "name": "approvalRequests",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          (v6/*:: as any*/),
          (v9/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "requestedAction",
            "storageKey": null
          },
          (v10/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "scopeType",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "scopeId",
            "storageKey": null
          },
          (v11/*:: as any*/),
          (v12/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "externalWrite",
            "storageKey": null
          },
          (v3/*:: as any*/),
          (v8/*:: as any*/),
          (v13/*:: as any*/),
          (v14/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorRunConversationContextExpansionRequest",
        "kind": "LinkedField",
        "name": "contextExpansionRequests",
        "plural": true,
        "selections": [
          (v4/*:: as any*/),
          (v6/*:: as any*/),
          (v9/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "targetResourceType",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "targetResourceId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "targetScopeType",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "targetScopeId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "accessMode",
            "storageKey": null
          },
          (v11/*:: as any*/),
          (v10/*:: as any*/),
          (v12/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "expectedDurationSeconds",
            "storageKey": null
          },
          (v3/*:: as any*/),
          (v8/*:: as any*/),
          (v13/*:: as any*/),
          (v14/*:: as any*/)
        ],
        "storageKey": null
      }
    ],
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "OperatorRunConversationQuery",
    "selections": (v15/*:: as any*/),
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v1/*:: as any*/),
      (v0/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "OperatorRunConversationQuery",
    "selections": (v15/*:: as any*/)
  },
  "params": {
    "cacheID": "6d23d24b1256b0fd943a21835cd574bf",
    "id": null,
    "metadata": {},
    "name": "OperatorRunConversationQuery",
    "operationKind": "query",
    "text": "query OperatorRunConversationQuery(\n  $runId: ID!\n  $graphItemId: ID!\n) {\n  operatorRunConversation(runId: $runId, graphItemId: $graphItemId) {\n    type\n    sourceWatermark\n    allowedNextActions\n    commandAffordances {\n      identity\n      state\n      reasonCodes\n      blockerReasons\n      safeExplanation\n      requiredFields\n      inputDefaults {\n        field\n        value\n        values\n      }\n      targetIds {\n        type\n        id\n      }\n    }\n    conversation {\n      id\n      runId\n      graphItemId\n      state\n      stateVersion\n    }\n    messages {\n      id\n      source\n      body\n      executionId\n      insertedAt\n      referencedContext {\n        visibility\n        packageId\n        version\n        entries {\n          posture\n          rationaleCode\n        }\n      }\n    }\n    executions {\n      id\n      bindingId\n      state\n      stateVersion\n      currentStepKey\n      attemptCount\n      failureCode\n      requestedOutcome\n      invocationMode\n      origin\n      autonomyMode\n      insertedAt\n      updatedAt\n    }\n    approvalRequests {\n      id\n      executionId\n      stepKey\n      requestedAction\n      reason\n      scopeType\n      scopeId\n      capabilityKey\n      sensitivity\n      externalWrite\n      state\n      version\n      expiresAt\n      resolutionReason\n    }\n    contextExpansionRequests {\n      id\n      executionId\n      stepKey\n      targetResourceType\n      targetResourceId\n      targetScopeType\n      targetScopeId\n      accessMode\n      capabilityKey\n      reason\n      sensitivity\n      expectedDurationSeconds\n      state\n      version\n      expiresAt\n      resolutionReason\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "713564ea8a02fcd075b7098fd4f38e06";

export default node;
