/**
 * @generated SignedSource<<338074bafd42b604b81deee02ee9ff12>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type PacketsRouteQuery$variables = {
  after?: string | null | undefined;
  first: number;
};
export type PacketsRouteQuery$data = {
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
  "name": "first"
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v3 = {
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
    (v2/*:: as any*/)
  ],
  "storageKey": null
},
v4 = [
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
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v7 = [
  (v6/*:: as any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "title",
    "storageKey": null
  },
  (v2/*:: as any*/),
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
v8 = {
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
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*:: as any*/),
      (v1/*:: as any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "PacketsRouteQuery",
    "selections": [
      (v3/*:: as any*/),
      {
        "alias": null,
        "args": (v4/*:: as any*/),
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
              (v5/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "WorkPacket",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": [
                  (v6/*:: as any*/),
                  {
                    "kind": "InlineDataFragmentSpread",
                    "name": "PacketsRoutePacketFragment",
                    "selections": (v7/*:: as any*/),
                    "args": null,
                    "argumentDefinitions": []
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v8/*:: as any*/)
        ],
        "storageKey": null
      }
    ],
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
    "name": "PacketsRouteQuery",
    "selections": [
      (v3/*:: as any*/),
      {
        "alias": null,
        "args": (v4/*:: as any*/),
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
              (v5/*:: as any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "WorkPacket",
                "kind": "LinkedField",
                "name": "node",
                "plural": false,
                "selections": (v7/*:: as any*/),
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v8/*:: as any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "cacheID": "7082f14d192643c9f622d41a33883788",
    "id": null,
    "metadata": {},
    "name": "PacketsRouteQuery",
    "operationKind": "query",
    "text": "query PacketsRouteQuery(\n  $first: Int!\n  $after: String\n) {\n  operatorPacketCreateAffordance {\n    identity\n    state\n  }\n  listWorkPackets(first: $first, after: $after) {\n    edges {\n      cursor\n      node {\n        id\n        ...PacketsRoutePacketFragment\n      }\n    }\n    pageInfo {\n      hasNextPage\n      hasPreviousPage\n      startCursor\n      endCursor\n    }\n  }\n}\n\nfragment PacketsRoutePacketFragment on WorkPacket {\n  id\n  title\n  state\n  currentVersionId\n  operationId\n  updatedAt\n}\n"
  }
};
})();

(node as any).hash = "28821dac996b0f1937303350af4388cc";

export default node;
