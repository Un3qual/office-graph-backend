/**
 * @generated SignedSource<<20f07516c1f8aba7107307c2849b9dc5>>
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
  readonly conversation: {
    readonly agentExecutions: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly approvalRequests: {
            readonly edges: ReadonlyArray<{
              readonly node: {
                readonly capabilityKey: string | null | undefined;
                readonly execution: {
                  readonly id: string;
                };
                readonly expiresAt: string;
                readonly externalWrite: boolean;
                readonly id: string;
                readonly insertedAt: string;
                readonly reason: string;
                readonly requestedAction: string;
                readonly resolutionReason: string | null | undefined;
                readonly scopeId: string;
                readonly scopeType: string;
                readonly sensitivity: string;
                readonly state: string;
                readonly stepKey: string;
                readonly version: number;
              };
            }> | null | undefined;
          };
          readonly attemptCount: number;
          readonly autonomyMode: string;
          readonly contextExpansionRequests: {
            readonly edges: ReadonlyArray<{
              readonly node: {
                readonly accessMode: string;
                readonly capabilityKey: string | null | undefined;
                readonly execution: {
                  readonly id: string;
                };
                readonly expectedDurationSeconds: number;
                readonly expiresAt: string;
                readonly id: string;
                readonly insertedAt: string;
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
              };
            }> | null | undefined;
          };
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
        };
      }> | null | undefined;
    };
    readonly graphItem: {
      readonly id: string;
    };
    readonly id: string;
    readonly messages: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly body: string;
          readonly execution: {
            readonly id: string;
          } | null | undefined;
          readonly id: string;
          readonly insertedAt: string;
          readonly source: string;
        };
      }> | null | undefined;
    };
    readonly run: {
      readonly id: string;
    };
    readonly state: string;
    readonly stateVersion: number;
  } | null | undefined;
  readonly operatorRunConversation: {
    readonly allowedNextActions: ReadonlyArray<string>;
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
    readonly messageContexts: ReadonlyArray<{
      readonly messageId: string;
      readonly referencedContext: {
        readonly entries: ReadonlyArray<{
          readonly posture: string;
          readonly rationaleCode: string;
        }>;
        readonly packageId: string | null | undefined;
        readonly version: number | null | undefined;
        readonly visibility: string;
      } | null | undefined;
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
v2 = [
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
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "type",
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
  "name": "id",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "version",
  "storageKey": null
},
v7 = [
  (v5/*:: as any*/)
],
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stateVersion",
  "storageKey": null
},
v9 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  },
  {
    "kind": "Literal",
    "name": "sort",
    "value": [
      {
        "field": "INSERTED_AT",
        "order": "DESC"
      }
    ]
  }
],
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "insertedAt",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "concreteType": "AgentExecution",
  "kind": "LinkedField",
  "name": "execution",
  "plural": false,
  "selections": (v7/*:: as any*/),
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stepKey",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "reason",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "capabilityKey",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sensitivity",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "expiresAt",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resolutionReason",
  "storageKey": null
},
v18 = [
  {
    "alias": null,
    "args": (v2/*:: as any*/),
    "concreteType": "OperatorRunConversation",
    "kind": "LinkedField",
    "name": "operatorRunConversation",
    "plural": false,
    "selections": [
      (v3/*:: as any*/),
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
          (v4/*:: as any*/),
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
              (v3/*:: as any*/),
              (v5/*:: as any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorRunConversationMessageContext",
        "kind": "LinkedField",
        "name": "messageContexts",
        "plural": true,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "messageId",
            "storageKey": null
          },
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
              (v6/*:: as any*/),
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
      }
    ],
    "storageKey": null
  },
  {
    "alias": "conversation",
    "args": (v2/*:: as any*/),
    "concreteType": "Conversation",
    "kind": "LinkedField",
    "name": "conversationForRunGraphItem",
    "plural": false,
    "selections": [
      (v5/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "concreteType": "WorkRun",
        "kind": "LinkedField",
        "name": "run",
        "plural": false,
        "selections": (v7/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "GraphItem",
        "kind": "LinkedField",
        "name": "graphItem",
        "plural": false,
        "selections": (v7/*:: as any*/),
        "storageKey": null
      },
      (v4/*:: as any*/),
      (v8/*:: as any*/),
      {
        "alias": null,
        "args": (v9/*:: as any*/),
        "concreteType": "ConversationMessageConnection",
        "kind": "LinkedField",
        "name": "messages",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "ConversationMessageEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "ConversationMessage",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  (v5/*:: as any*/),
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
                  (v10/*:: as any*/),
                  (v11/*:: as any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": "messages(first:100,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"DESC\"}])"
      },
      {
        "alias": null,
        "args": (v9/*:: as any*/),
        "concreteType": "AgentExecutionConnection",
        "kind": "LinkedField",
        "name": "agentExecutions",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "AgentExecutionEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "AgentExecution",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  (v5/*:: as any*/),
                  (v4/*:: as any*/),
                  (v8/*:: as any*/),
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
                  (v10/*:: as any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "updatedAt",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": (v9/*:: as any*/),
                    "concreteType": "AgentApprovalRequestConnection",
                    "kind": "LinkedField",
                    "name": "approvalRequests",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "AgentApprovalRequestEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "AgentApprovalRequest",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": [
                              (v5/*:: as any*/),
                              (v11/*:: as any*/),
                              (v12/*:: as any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "requestedAction",
                                "storageKey": null
                              },
                              (v13/*:: as any*/),
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
                              (v14/*:: as any*/),
                              (v15/*:: as any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "externalWrite",
                                "storageKey": null
                              },
                              (v4/*:: as any*/),
                              (v6/*:: as any*/),
                              (v16/*:: as any*/),
                              (v17/*:: as any*/),
                              (v10/*:: as any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "approvalRequests(first:100,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"DESC\"}])"
                  },
                  {
                    "alias": null,
                    "args": (v9/*:: as any*/),
                    "concreteType": "AgentContextExpansionRequestConnection",
                    "kind": "LinkedField",
                    "name": "contextExpansionRequests",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "AgentContextExpansionRequestEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "AgentContextExpansionRequest",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": [
                              (v5/*:: as any*/),
                              (v11/*:: as any*/),
                              (v12/*:: as any*/),
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
                              (v14/*:: as any*/),
                              (v13/*:: as any*/),
                              (v15/*:: as any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "expectedDurationSeconds",
                                "storageKey": null
                              },
                              (v4/*:: as any*/),
                              (v6/*:: as any*/),
                              (v16/*:: as any*/),
                              (v17/*:: as any*/),
                              (v10/*:: as any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "contextExpansionRequests(first:100,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"DESC\"}])"
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": "agentExecutions(first:100,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"DESC\"}])"
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
    "metadata": {
      "throwOnFieldError": true
    },
    "name": "OperatorRunConversationQuery",
    "selections": (v18/*:: as any*/),
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
    "selections": (v18/*:: as any*/)
  },
  "params": {
    "cacheID": "21ef484436d507215d6222d54e8b6ee1",
    "id": null,
    "metadata": {},
    "name": "OperatorRunConversationQuery",
    "operationKind": "query",
    "text": "query OperatorRunConversationQuery(\n  $runId: ID!\n  $graphItemId: ID!\n) {\n  operatorRunConversation(runId: $runId, graphItemId: $graphItemId) {\n    type\n    sourceWatermark\n    allowedNextActions\n    commandAffordances {\n      identity\n      state\n      reasonCodes\n      blockerReasons\n      safeExplanation\n      requiredFields\n      inputDefaults {\n        field\n        value\n        values\n      }\n      targetIds {\n        type\n        id\n      }\n    }\n    messageContexts {\n      messageId\n      referencedContext {\n        visibility\n        packageId\n        version\n        entries {\n          posture\n          rationaleCode\n        }\n      }\n    }\n  }\n  conversation: conversationForRunGraphItem(runId: $runId, graphItemId: $graphItemId) {\n    id\n    run {\n      id\n    }\n    graphItem {\n      id\n    }\n    state\n    stateVersion\n    messages(first: 100, sort: [{field: INSERTED_AT, order: DESC}]) {\n      edges {\n        node {\n          id\n          source\n          body\n          insertedAt\n          execution {\n            id\n          }\n        }\n      }\n    }\n    agentExecutions(first: 100, sort: [{field: INSERTED_AT, order: DESC}]) {\n      edges {\n        node {\n          id\n          state\n          stateVersion\n          currentStepKey\n          attemptCount\n          failureCode\n          requestedOutcome\n          invocationMode\n          origin\n          autonomyMode\n          insertedAt\n          updatedAt\n          approvalRequests(first: 100, sort: [{field: INSERTED_AT, order: DESC}]) {\n            edges {\n              node {\n                id\n                execution {\n                  id\n                }\n                stepKey\n                requestedAction\n                reason\n                scopeType\n                scopeId\n                capabilityKey\n                sensitivity\n                externalWrite\n                state\n                version\n                expiresAt\n                resolutionReason\n                insertedAt\n              }\n            }\n          }\n          contextExpansionRequests(first: 100, sort: [{field: INSERTED_AT, order: DESC}]) {\n            edges {\n              node {\n                id\n                execution {\n                  id\n                }\n                stepKey\n                targetResourceType\n                targetResourceId\n                targetScopeType\n                targetScopeId\n                accessMode\n                capabilityKey\n                reason\n                sensitivity\n                expectedDurationSeconds\n                state\n                version\n                expiresAt\n                resolutionReason\n                insertedAt\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "2b6a2efa40e28dbea52e4767553789eb";

export default node;
