/**
 * @generated SignedSource<<49b4b1ee77aed7c87e421a3798310d7e>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type AcceptEvidenceInput = {
  acceptancePolicyBasis: string;
  body: string;
  evidenceCandidateId: string;
  idempotencyKey: string;
  result: string;
  title: string;
};
export type OperatorAcceptEvidenceMutation$variables = {
  input: AcceptEvidenceInput;
};
export type OperatorAcceptEvidenceMutation$data = {
  readonly acceptEvidence: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    } | null | undefined>;
    readonly command: string;
    readonly evidenceCandidate: {
      readonly candidateState: string;
      readonly id: string;
    };
    readonly evidenceItem: {
      readonly id: string;
      readonly state: string;
    };
    readonly operationId: string;
  };
};
export type OperatorAcceptEvidenceMutation = {
  response: OperatorAcceptEvidenceMutation$data;
  variables: OperatorAcceptEvidenceMutation$variables;
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
    "concreteType": "AcceptEvidencePayload",
    "kind": "LinkedField",
    "name": "acceptEvidence",
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
        "concreteType": "EvidenceCandidate",
        "kind": "LinkedField",
        "name": "evidenceCandidate",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "candidateState",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "EvidenceItem",
        "kind": "LinkedField",
        "name": "evidenceItem",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "state",
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
    "name": "OperatorAcceptEvidenceMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorAcceptEvidenceMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "44447d30a7c3711dae9e6b2c63c11db5",
    "id": null,
    "metadata": {},
    "name": "OperatorAcceptEvidenceMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorAcceptEvidenceMutation(\n  $input: AcceptEvidenceInput!\n) {\n  acceptEvidence(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    evidenceCandidate {\n      id\n      candidateState\n    }\n    evidenceItem {\n      id\n      state\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "f47f91ab86ad6cb7120bdb8bb0a0d2bd";

export default node;
