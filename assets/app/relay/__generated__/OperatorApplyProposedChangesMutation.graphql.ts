/**
 * @generated SignedSource<<65839e4396ecbfddc6f9dd4fe8d877aa>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type ApplyProposedChangesInput = {
  idempotencyKey: string;
  normalizedEventId: string;
  proposedChangeIds: ReadonlyArray<string>;
};
export type OperatorApplyProposedChangesMutation$variables = {
  input: ApplyProposedChangesInput;
};
export type OperatorApplyProposedChangesMutation$data = {
  readonly applyProposedChanges: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    } | null | undefined>;
    readonly command: string;
    readonly operationId: string;
    readonly reviewFinding: {
      readonly id: string;
    };
    readonly signal: {
      readonly id: string;
    };
    readonly task: {
      readonly id: string;
    };
    readonly verificationCheck: {
      readonly graphItemId: string;
      readonly id: string;
    };
  };
};
export type OperatorApplyProposedChangesMutation = {
  response: OperatorApplyProposedChangesMutation$data;
  variables: OperatorApplyProposedChangesMutation$variables;
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
  (v1/*:: as any*/)
],
v3 = [
  {
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "input",
        "variableName": "input"
      }
    ],
    "concreteType": "ApplyProposedChangesPayload",
    "kind": "LinkedField",
    "name": "applyProposedChanges",
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
        "concreteType": "Signal",
        "kind": "LinkedField",
        "name": "signal",
        "plural": false,
        "selections": (v2/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "Task",
        "kind": "LinkedField",
        "name": "task",
        "plural": false,
        "selections": (v2/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "ReviewFinding",
        "kind": "LinkedField",
        "name": "reviewFinding",
        "plural": false,
        "selections": (v2/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "VerificationCheck",
        "kind": "LinkedField",
        "name": "verificationCheck",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "graphItemId",
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
    "name": "OperatorApplyProposedChangesMutation",
    "selections": (v3/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorApplyProposedChangesMutation",
    "selections": (v3/*:: as any*/)
  },
  "params": {
    "cacheID": "5ca9163f83a43004a265cc5ce5e1189a",
    "id": null,
    "metadata": {},
    "name": "OperatorApplyProposedChangesMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorApplyProposedChangesMutation(\n  $input: ApplyProposedChangesInput!\n) {\n  applyProposedChanges(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    signal {\n      id\n    }\n    task {\n      id\n    }\n    reviewFinding {\n      id\n    }\n    verificationCheck {\n      id\n      graphItemId\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "f51675a07b8c380558932513171e7a23";

export default node;
