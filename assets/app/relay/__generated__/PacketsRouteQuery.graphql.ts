/**
 * @generated SignedSource<<0a50ab37deaa5d70d0247363269ad325>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type PacketsRouteQuery$variables = {
  after?: string | null | undefined;
  createdOperationId?: string | null | undefined;
  first: number;
  loadCreatedPacket: boolean;
  loadLinkedPacket: boolean;
  packetId: string;
};
export type PacketsRouteQuery$data = {
  readonly createdPacket?: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly id: string;
        readonly " $fragmentSpreads": FragmentRefs<"PacketsRoutePacketFragment">;
      };
    }> | null | undefined;
  } | null | undefined;
  readonly linkedPacket?: {
    readonly id: string;
    readonly " $fragmentSpreads": FragmentRefs<"PacketsRoutePacketFragment">;
  } | null | undefined;
  readonly listWorkPackets: {
    readonly edges: ReadonlyArray<{
      readonly cursor: string;
      readonly node: {
        readonly id: string;
        readonly " $fragmentSpreads": FragmentRefs<"PacketsRoutePacketFragment">;
      };
    }> | null | undefined;
    readonly pageInfo: {
      readonly endCursor: string | null | undefined;
      readonly hasNextPage: boolean;
      readonly hasPreviousPage: boolean;
      readonly startCursor: string | null | undefined;
    };
  } | null | undefined;
  readonly operatorPacketCreateAffordance: {
    readonly identity: string;
    readonly state: string;
  };
};
export type PacketsRouteQuery = {
  response: PacketsRouteQuery$data;
  variables: PacketsRouteQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "after"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "createdOperationId"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "loadCreatedPacket"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "loadLinkedPacket"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "packetId"
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
  "concreteType": "OperatorCommandAffordance",
  "kind": "LinkedField",
  "name": "operatorPacketCreateAffordance",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "identity",
      "storageKey": null
    },
    (v6/*:: as any*/)
  ],
  "storageKey": null
},
v8 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "after"
  },
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "first"
  }
],
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v11 = [
  (v10/*:: as any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "title",
    "storageKey": null
  },
  (v6/*:: as any*/),
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
    "name": "operationId",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "updatedAt",
    "storageKey": null
  }
],
v12 = [
  (v10/*:: as any*/),
  {
    "kind": "InlineDataFragmentSpread",
    "name": "PacketsRoutePacketFragment",
    "selections": (v11/*:: as any*/),
    "args": null,
    "argumentDefinitions": ([]/*:: as any*/)
  }
],
v13 = {
  "alias": null,
  "args": null,
  "concreteType": "WorkPacket",
  "kind": "LinkedField",
  "name": "node",
  "plural": false,
  "selections": (v12/*:: as any*/),
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasNextPage",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasPreviousPage",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "startCursor",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "endCursor",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v15 = [
  {
    "fields": [
      {
        "fields": [
          {
            "kind": "Variable",
            "name": "eq",
            "variableName": "createdOperationId"
          }
        ],
        "kind": "ObjectValue",
        "name": "operationId"
      }
    ],
    "kind": "ObjectValue",
    "name": "filter"
  },
  {
    "kind": "Literal",
    "name": "first",
    "value": 1
  }
],
v16 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "packetId"
  }
],
v17 = {
  "alias": null,
  "args": null,
  "concreteType": "WorkPacket",
  "kind": "LinkedField",
  "name": "node",
  "plural": false,
  "selections": (v11/*:: as any*/),
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/),
      (v2/*:: as any*/),
      (v3/*:: as any*/),
      (v4/*:: as any*/),
      (v5/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "PacketsRouteQuery",
    "selections": [
      (v7/*:: as any*/),
      {
        "alias": null,
        "args": (v8/*:: as any*/),
        "concreteType": "WorkPacketConnection",
        "kind": "LinkedField",
        "name": "listWorkPackets",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "WorkPacketEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              (v9/*:: as any*/),
              (v13/*:: as any*/)
            ],
            "storageKey": null
          },
          (v14/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "condition": "loadCreatedPacket",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "createdPacket",
            "args": (v15/*:: as any*/),
            "concreteType": "WorkPacketConnection",
            "kind": "LinkedField",
            "name": "listWorkPackets",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "WorkPacketEdge",
                "kind": "LinkedField",
                "name": "edges",
                "plural": true,
                "selections": [
                  (v13/*:: as any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadLinkedPacket",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "kind": "CatchField",
            "field": {
              "alias": "linkedPacket",
              "args": (v16/*:: as any*/),
              "concreteType": "WorkPacket",
              "kind": "LinkedField",
              "name": "getWorkPacket",
              "plural": false,
              "selections": (v12/*:: as any*/),
              "storageKey": null
            },
            "to": "NULL"
          }
        ]
      }
    ],
    "type": "RootQueryType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v2/*:: as any*/),
      (v0/*:: as any*/),
      (v1/*:: as any*/),
      (v3/*:: as any*/),
      (v5/*:: as any*/),
      (v4/*:: as any*/)
    ],
    "kind": "Operation",
    "name": "PacketsRouteQuery",
    "selections": [
      (v7/*:: as any*/),
      {
        "alias": null,
        "args": (v8/*:: as any*/),
        "concreteType": "WorkPacketConnection",
        "kind": "LinkedField",
        "name": "listWorkPackets",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "WorkPacketEdge",
            "kind": "LinkedField",
            "name": "edges",
            "plural": true,
            "selections": [
              (v9/*:: as any*/),
              (v17/*:: as any*/)
            ],
            "storageKey": null
          },
          (v14/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "condition": "loadCreatedPacket",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "createdPacket",
            "args": (v15/*:: as any*/),
            "concreteType": "WorkPacketConnection",
            "kind": "LinkedField",
            "name": "listWorkPackets",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "WorkPacketEdge",
                "kind": "LinkedField",
                "name": "edges",
                "plural": true,
                "selections": [
                  (v17/*:: as any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ]
      },
      {
        "condition": "loadLinkedPacket",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": "linkedPacket",
            "args": (v16/*:: as any*/),
            "concreteType": "WorkPacket",
            "kind": "LinkedField",
            "name": "getWorkPacket",
            "plural": false,
            "selections": (v11/*:: as any*/),
            "storageKey": null
          }
        ]
      }
    ]
  },
  "params": {
    "cacheID": "c5b0f984b97c6ea89f2e3ee4fc9ada95",
    "id": null,
    "metadata": {},
    "name": "PacketsRouteQuery",
    "operationKind": "query",
    "text": "query PacketsRouteQuery(\n  $first: Int!\n  $after: String\n  $createdOperationId: ID\n  $loadCreatedPacket: Boolean!\n  $packetId: ID!\n  $loadLinkedPacket: Boolean!\n) {\n  operatorPacketCreateAffordance {\n    identity\n    state\n  }\n  listWorkPackets(first: $first, after: $after) {\n    edges {\n      cursor\n      node {\n        id\n        ...PacketsRoutePacketFragment\n      }\n    }\n    pageInfo {\n      hasNextPage\n      hasPreviousPage\n      startCursor\n      endCursor\n    }\n  }\n  createdPacket: listWorkPackets(first: 1, filter: {operationId: {eq: $createdOperationId}}) @include(if: $loadCreatedPacket) {\n    edges {\n      node {\n        id\n        ...PacketsRoutePacketFragment\n      }\n    }\n  }\n  linkedPacket: getWorkPacket(id: $packetId) @include(if: $loadLinkedPacket) {\n    id\n    ...PacketsRoutePacketFragment\n  }\n}\n\nfragment PacketsRoutePacketFragment on WorkPacket {\n  id\n  title\n  state\n  currentVersionId\n  operationId\n  updatedAt\n}\n"
  }
};
})();

(node as any).hash = "7450b6f0e83f7eedea7addc640711352";

export default node;
