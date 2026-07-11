/**
 * @generated SignedSource<<42718fac8a8ff27672621d4c661b6872>>
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
    }>;
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
    readonly run: {
      readonly executionState: string;
      readonly id: string;
      readonly verificationState: string;
    } | null | undefined;
    readonly verificationResult: {
      readonly id: string;
      readonly result: string;
    };
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
        "concreteType": "OperatorCommandEvidenceCandidate",
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
        "concreteType": "OperatorCommandEvidenceItem",
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
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandVerificationResult",
        "kind": "LinkedField",
        "name": "verificationResult",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "result",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "OperatorCommandWorkRun",
        "kind": "LinkedField",
        "name": "run",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "executionState",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "verificationState",
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
    "cacheID": "a77e098986b83758f67391d091878f3b",
    "id": null,
    "metadata": {},
    "name": "OperatorAcceptEvidenceMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorAcceptEvidenceMutation(\n  $input: AcceptEvidenceInput!\n) {\n  acceptEvidence(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    evidenceCandidate {\n      id\n      candidateState\n    }\n    evidenceItem {\n      id\n      state\n    }\n    verificationResult {\n      id\n      result\n    }\n    run {\n      id\n      executionState\n      verificationState\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "c5c6df8c0df7c459c1bc0ea720f0afa5";

export default node;
