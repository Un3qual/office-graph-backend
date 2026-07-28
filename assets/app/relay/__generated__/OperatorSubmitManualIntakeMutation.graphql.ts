/**
 * @generated SignedSource<<11ef9752ba5e3dbddf366b4b3a462264>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type SubmitManualIntakeInput = {
  body: string;
  idempotencyKey: string;
  replayIdentity: string;
  sourceIdentity: string;
};
export type OperatorSubmitManualIntakeMutation$variables = {
  input: SubmitManualIntakeInput;
};
export type OperatorSubmitManualIntakeMutation$data = {
  readonly submitManualIntake: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    } | null | undefined>;
    readonly command: string;
    readonly normalizedEvent: {
      readonly id: string;
    };
    readonly operationId: string;
    readonly proposedChanges: ReadonlyArray<{
      readonly id: string;
    }>;
  };
};
export type OperatorSubmitManualIntakeMutation = {
  response: OperatorSubmitManualIntakeMutation$data;
  variables: OperatorSubmitManualIntakeMutation$variables;
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
    "concreteType": "SubmitManualIntakePayload",
    "kind": "LinkedField",
    "name": "submitManualIntake",
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
        "concreteType": "NormalizedIntakeEvent",
        "kind": "LinkedField",
        "name": "normalizedEvent",
        "plural": false,
        "selections": (v2/*:: as any*/),
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "ProposedGraphChange",
        "kind": "LinkedField",
        "name": "proposedChanges",
        "plural": true,
        "selections": (v2/*:: as any*/),
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
    "name": "OperatorSubmitManualIntakeMutation",
    "selections": (v3/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorSubmitManualIntakeMutation",
    "selections": (v3/*:: as any*/)
  },
  "params": {
    "cacheID": "049d8a286ebcc88421205552dbca3817",
    "id": null,
    "metadata": {},
    "name": "OperatorSubmitManualIntakeMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorSubmitManualIntakeMutation(\n  $input: SubmitManualIntakeInput!\n) {\n  submitManualIntake(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    normalizedEvent {\n      id\n    }\n    proposedChanges {\n      id\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "4b101e1161d48d0ec22dde7e6724afe3";

export default node;
