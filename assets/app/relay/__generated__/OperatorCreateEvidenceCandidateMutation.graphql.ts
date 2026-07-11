/**
 * @generated SignedSource<<28825dd4288f418da63508fc194d02ea>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type CreateEvidenceCandidateInput = {
  claim: string;
  executionObservationId: string;
  freshnessState: string;
  idempotencyKey: string;
  sensitivity: string;
  sourceIdentity: string;
  sourceKind: string;
  trustBasis: string;
  verificationCheckId: string;
  workRunId: string;
};
export type OperatorCreateEvidenceCandidateMutation$variables = {
  input: CreateEvidenceCandidateInput;
};
export type OperatorCreateEvidenceCandidateMutation$data = {
  readonly createEvidenceCandidate: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly evidenceCandidate: {
      readonly candidateState: string;
      readonly id: string;
    };
    readonly operationId: string;
  };
};
export type OperatorCreateEvidenceCandidateMutation = {
  response: OperatorCreateEvidenceCandidateMutation$data;
  variables: OperatorCreateEvidenceCandidateMutation$variables;
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
    "concreteType": "CreateEvidenceCandidatePayload",
    "kind": "LinkedField",
    "name": "createEvidenceCandidate",
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
    "name": "OperatorCreateEvidenceCandidateMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorCreateEvidenceCandidateMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "5f2f7a9b5d0ec9ce16c4359fedf061b1",
    "id": null,
    "metadata": {},
    "name": "OperatorCreateEvidenceCandidateMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorCreateEvidenceCandidateMutation(\n  $input: CreateEvidenceCandidateInput!\n) {\n  createEvidenceCandidate(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    evidenceCandidate {\n      id\n      candidateState\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "4c57e209ab9bedc42a7c5e00be349f2f";

export default node;
