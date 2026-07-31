/**
 * @generated SignedSource<<bdc499d1b9a46ac58a71f089566b4658>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type OperatorRunConversationQuery$variables = {
  graphItemId: string;
  graphItemRelayId: string;
  runId: string;
  runRelayId: string;
};
export type OperatorRunConversationQuery$data = {
  readonly activeAgentExecutions: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly attemptCount: number;
        readonly autonomyMode: string;
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
  } | null | undefined;
  readonly conversation: {
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
    readonly id: string;
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
  readonly pendingAgentApprovalRequests: {
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
  } | null | undefined;
  readonly pendingAgentContextExpansionRequests: {
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
  } | null | undefined;
  readonly resolvedAgentApprovalRequests: {
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
  } | null | undefined;
  readonly resolvedAgentContextExpansionRequests: {
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
  } | null | undefined;
  readonly terminalAgentExecutions: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly attemptCount: number;
        readonly autonomyMode: string;
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
  } | null | undefined;
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
  "name": "graphItemRelayId"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "runId"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "runRelayId"
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
  "name": "type",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "version",
  "storageKey": null
},
v8 = [
  (v4/*:: as any*/)
],
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stateVersion",
  "storageKey": null
},
v10 = {
  "kind": "Literal",
  "name": "first",
  "value": 100
},
v11 = {
  "field": "INSERTED_AT",
  "order": "DESC"
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "insertedAt",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "concreteType": "AgentExecution",
  "kind": "LinkedField",
  "name": "execution",
  "plural": false,
  "selections": (v8/*:: as any*/),
  "storageKey": null
},
v14 = {
  "fields": [
    {
      "kind": "Variable",
      "name": "eq",
      "variableName": "graphItemId"
    }
  ],
  "kind": "ObjectValue",
  "name": "graphItemId"
},
v15 = {
  "fields": [
    {
      "kind": "Variable",
      "name": "eq",
      "variableName": "runId"
    }
  ],
  "kind": "ObjectValue",
  "name": "runId"
},
v16 = {
  "kind": "Literal",
  "name": "sort",
  "value": [
    (v11/*:: as any*/),
    {
      "field": "ID",
      "order": "DESC"
    }
  ]
},
v17 = [
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
          (v4/*:: as any*/),
          (v6/*:: as any*/),
          (v9/*:: as any*/),
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
          (v12/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "updatedAt",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v18 = {
  "fields": [
    (v14/*:: as any*/),
    (v15/*:: as any*/)
  ],
  "kind": "ObjectValue",
  "name": "execution"
},
v19 = [
  {
    "fields": [
      (v18/*:: as any*/),
      {
        "kind": "Literal",
        "name": "state",
        "value": {
          "eq": "pending"
        }
      }
    ],
    "kind": "ObjectValue",
    "name": "filter"
  },
  (v10/*:: as any*/),
  (v16/*:: as any*/)
],
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stepKey",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "reason",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "capabilityKey",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "sensitivity",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "expiresAt",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resolutionReason",
  "storageKey": null
},
v26 = [
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
          (v4/*:: as any*/),
          (v13/*:: as any*/),
          (v20/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "requestedAction",
            "storageKey": null
          },
          (v21/*:: as any*/),
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
          (v22/*:: as any*/),
          (v23/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "externalWrite",
            "storageKey": null
          },
          (v6/*:: as any*/),
          (v7/*:: as any*/),
          (v24/*:: as any*/),
          (v25/*:: as any*/),
          (v12/*:: as any*/)
        ],
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v27 = [
  {
    "fields": [
      (v18/*:: as any*/),
      {
        "kind": "Literal",
        "name": "state",
        "value": {
          "notEq": "pending"
        }
      }
    ],
    "kind": "ObjectValue",
    "name": "filter"
  },
  (v10/*:: as any*/),
  (v16/*:: as any*/)
],
v28 = [
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
          (v4/*:: as any*/),
          (v13/*:: as any*/),
          (v20/*:: as any*/),
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
          (v22/*:: as any*/),
          (v21/*:: as any*/),
          (v23/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "expectedDurationSeconds",
            "storageKey": null
          },
          (v6/*:: as any*/),
          (v7/*:: as any*/),
          (v24/*:: as any*/),
          (v25/*:: as any*/),
          (v12/*:: as any*/)
        ],
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v29 = [
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
      (v4/*:: as any*/),
      (v5/*:: as any*/),
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
          (v6/*:: as any*/),
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
              (v5/*:: as any*/),
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
              (v7/*:: as any*/),
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
    "args": [
      {
        "kind": "Variable",
        "name": "graphItemId",
        "variableName": "graphItemRelayId"
      },
      {
        "kind": "Variable",
        "name": "runId",
        "variableName": "runRelayId"
      }
    ],
    "concreteType": "Conversation",
    "kind": "LinkedField",
    "name": "conversationForRunGraphItem",
    "plural": false,
    "selections": [
      (v4/*:: as any*/),
      {
        "alias": null,
        "args": null,
        "concreteType": "WorkRun",
        "kind": "LinkedField",
        "name": "run",
        "plural": false,
        "selections": (v8/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "GraphItem",
        "kind": "LinkedField",
        "name": "graphItem",
        "plural": false,
        "selections": (v8/*:: as any*/),
        "storageKey": null
      },
      (v6/*:: as any*/),
      (v9/*:: as any*/),
      {
        "alias": null,
        "args": [
          (v10/*:: as any*/),
          {
            "kind": "Literal",
            "name": "sort",
            "value": [
              (v11/*:: as any*/)
            ]
          }
        ],
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
                  (v12/*:: as any*/),
                  (v13/*:: as any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": "messages(first:100,sort:[{\"field\":\"INSERTED_AT\",\"order\":\"DESC\"}])"
      }
    ],
    "storageKey": null
  },
  {
    "alias": "activeAgentExecutions",
    "args": [
      {
        "fields": [
          (v14/*:: as any*/),
          (v15/*:: as any*/),
          {
            "kind": "Literal",
            "name": "state",
            "value": {
              "in": [
                "queued",
                "running",
                "waiting_approval",
                "waiting_context",
                "retry_scheduled"
              ]
            }
          }
        ],
        "kind": "ObjectValue",
        "name": "filter"
      },
      (v10/*:: as any*/),
      (v16/*:: as any*/)
    ],
    "concreteType": "AgentExecutionConnection",
    "kind": "LinkedField",
    "name": "listAgentExecutions",
    "plural": false,
    "selections": (v17/*:: as any*/),
    "storageKey": null
  },
  {
    "alias": "terminalAgentExecutions",
    "args": [
      {
        "fields": [
          (v14/*:: as any*/),
          (v15/*:: as any*/),
          {
            "kind": "Literal",
            "name": "state",
            "value": {
              "in": [
                "completed",
                "failed",
                "cancelled"
              ]
            }
          }
        ],
        "kind": "ObjectValue",
        "name": "filter"
      },
      (v10/*:: as any*/),
      (v16/*:: as any*/)
    ],
    "concreteType": "AgentExecutionConnection",
    "kind": "LinkedField",
    "name": "listAgentExecutions",
    "plural": false,
    "selections": (v17/*:: as any*/),
    "storageKey": null
  },
  {
    "alias": "pendingAgentApprovalRequests",
    "args": (v19/*:: as any*/),
    "concreteType": "AgentApprovalRequestConnection",
    "kind": "LinkedField",
    "name": "listAgentApprovalRequests",
    "plural": false,
    "selections": (v26/*:: as any*/),
    "storageKey": null
  },
  {
    "alias": "resolvedAgentApprovalRequests",
    "args": (v27/*:: as any*/),
    "concreteType": "AgentApprovalRequestConnection",
    "kind": "LinkedField",
    "name": "listAgentApprovalRequests",
    "plural": false,
    "selections": (v26/*:: as any*/),
    "storageKey": null
  },
  {
    "alias": "pendingAgentContextExpansionRequests",
    "args": (v19/*:: as any*/),
    "concreteType": "AgentContextExpansionRequestConnection",
    "kind": "LinkedField",
    "name": "listAgentContextExpansionRequests",
    "plural": false,
    "selections": (v28/*:: as any*/),
    "storageKey": null
  },
  {
    "alias": "resolvedAgentContextExpansionRequests",
    "args": (v27/*:: as any*/),
    "concreteType": "AgentContextExpansionRequestConnection",
    "kind": "LinkedField",
    "name": "listAgentContextExpansionRequests",
    "plural": false,
    "selections": (v28/*:: as any*/),
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/),
      (v2/*:: as any*/),
      (v3/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": {
      "throwOnFieldError": true
    },
    "name": "OperatorRunConversationQuery",
    "selections": (v29/*:: as any*/),
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v2/*:: as any*/),
      (v0/*:: as any*/),
      (v3/*:: as any*/),
      (v1/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "OperatorRunConversationQuery",
    "selections": (v29/*:: as any*/)
  },
  "params": {
    "cacheID": "35e37af836a6214d99a748d34aeba5ee",
    "id": null,
    "metadata": {},
    "name": "OperatorRunConversationQuery",
    "operationKind": "query",
    "text": "query OperatorRunConversationQuery(\n  $runId: ID!\n  $graphItemId: ID!\n  $runRelayId: ID!\n  $graphItemRelayId: ID!\n) {\n  operatorRunConversation(runId: $runId, graphItemId: $graphItemId) {\n    id\n    type\n    sourceWatermark\n    allowedNextActions\n    commandAffordances {\n      identity\n      state\n      reasonCodes\n      blockerReasons\n      safeExplanation\n      requiredFields\n      inputDefaults {\n        field\n        value\n        values\n      }\n      targetIds {\n        type\n        id\n      }\n    }\n    messageContexts {\n      messageId\n      referencedContext {\n        visibility\n        packageId\n        version\n        entries {\n          posture\n          rationaleCode\n        }\n      }\n    }\n  }\n  conversation: conversationForRunGraphItem(runId: $runRelayId, graphItemId: $graphItemRelayId) {\n    id\n    run {\n      id\n    }\n    graphItem {\n      id\n    }\n    state\n    stateVersion\n    messages(first: 100, sort: [{field: INSERTED_AT, order: DESC}]) {\n      edges {\n        node {\n          id\n          source\n          body\n          insertedAt\n          execution {\n            id\n          }\n        }\n      }\n    }\n  }\n  activeAgentExecutions: listAgentExecutions(first: 100, filter: {runId: {eq: $runId}, graphItemId: {eq: $graphItemId}, state: {in: [\"queued\", \"running\", \"waiting_approval\", \"waiting_context\", \"retry_scheduled\"]}}, sort: [{field: INSERTED_AT, order: DESC}, {field: ID, order: DESC}]) {\n    edges {\n      node {\n        id\n        state\n        stateVersion\n        currentStepKey\n        attemptCount\n        failureCode\n        requestedOutcome\n        invocationMode\n        origin\n        autonomyMode\n        insertedAt\n        updatedAt\n      }\n    }\n  }\n  terminalAgentExecutions: listAgentExecutions(first: 100, filter: {runId: {eq: $runId}, graphItemId: {eq: $graphItemId}, state: {in: [\"completed\", \"failed\", \"cancelled\"]}}, sort: [{field: INSERTED_AT, order: DESC}, {field: ID, order: DESC}]) {\n    edges {\n      node {\n        id\n        state\n        stateVersion\n        currentStepKey\n        attemptCount\n        failureCode\n        requestedOutcome\n        invocationMode\n        origin\n        autonomyMode\n        insertedAt\n        updatedAt\n      }\n    }\n  }\n  pendingAgentApprovalRequests: listAgentApprovalRequests(first: 100, filter: {execution: {runId: {eq: $runId}, graphItemId: {eq: $graphItemId}}, state: {eq: \"pending\"}}, sort: [{field: INSERTED_AT, order: DESC}, {field: ID, order: DESC}]) {\n    edges {\n      node {\n        id\n        execution {\n          id\n        }\n        stepKey\n        requestedAction\n        reason\n        scopeType\n        scopeId\n        capabilityKey\n        sensitivity\n        externalWrite\n        state\n        version\n        expiresAt\n        resolutionReason\n        insertedAt\n      }\n    }\n  }\n  resolvedAgentApprovalRequests: listAgentApprovalRequests(first: 100, filter: {execution: {runId: {eq: $runId}, graphItemId: {eq: $graphItemId}}, state: {notEq: \"pending\"}}, sort: [{field: INSERTED_AT, order: DESC}, {field: ID, order: DESC}]) {\n    edges {\n      node {\n        id\n        execution {\n          id\n        }\n        stepKey\n        requestedAction\n        reason\n        scopeType\n        scopeId\n        capabilityKey\n        sensitivity\n        externalWrite\n        state\n        version\n        expiresAt\n        resolutionReason\n        insertedAt\n      }\n    }\n  }\n  pendingAgentContextExpansionRequests: listAgentContextExpansionRequests(first: 100, filter: {execution: {runId: {eq: $runId}, graphItemId: {eq: $graphItemId}}, state: {eq: \"pending\"}}, sort: [{field: INSERTED_AT, order: DESC}, {field: ID, order: DESC}]) {\n    edges {\n      node {\n        id\n        execution {\n          id\n        }\n        stepKey\n        targetResourceType\n        targetResourceId\n        targetScopeType\n        targetScopeId\n        accessMode\n        capabilityKey\n        reason\n        sensitivity\n        expectedDurationSeconds\n        state\n        version\n        expiresAt\n        resolutionReason\n        insertedAt\n      }\n    }\n  }\n  resolvedAgentContextExpansionRequests: listAgentContextExpansionRequests(first: 100, filter: {execution: {runId: {eq: $runId}, graphItemId: {eq: $graphItemId}}, state: {notEq: \"pending\"}}, sort: [{field: INSERTED_AT, order: DESC}, {field: ID, order: DESC}]) {\n    edges {\n      node {\n        id\n        execution {\n          id\n        }\n        stepKey\n        targetResourceType\n        targetResourceId\n        targetScopeType\n        targetScopeId\n        accessMode\n        capabilityKey\n        reason\n        sensitivity\n        expectedDurationSeconds\n        state\n        version\n        expiresAt\n        resolutionReason\n        insertedAt\n      }\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "72a1d12d5a3eadb9fa24db1bd20f8e83";

export default node;
