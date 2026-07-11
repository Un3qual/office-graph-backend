/**
 * @generated SignedSource<<c6c8fde9c50a1217d1f7975dba16e6af>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type RecordExecutionObservationInput = {
  freshnessState: string;
  idempotencyKey: string;
  normalizedStatus: string;
  observationIdempotencyKey: string;
  observationRationale: string;
  observationSourceIdentity: string;
  observationSourceKind: string;
  observedStatus: string;
  runId: string;
  sourceGraphItemId: string;
  trustBasis: string;
  verificationCheckId: string;
};
export type OperatorRecordExecutionObservationMutation$variables = {
  input: RecordExecutionObservationInput;
};
export type OperatorRecordExecutionObservationMutation$data = {
  readonly recordExecutionObservation: {
    readonly affectedIds: ReadonlyArray<{
      readonly id: string;
      readonly type: string;
    }>;
    readonly command: string;
    readonly observation: {
      readonly id: string;
      readonly normalizedStatus: string;
    };
    readonly operationId: string;
    readonly run: {
      readonly executionState: string;
      readonly id: string;
      readonly verificationState: string;
    };
  };
};
export type OperatorRecordExecutionObservationMutation = {
  response: OperatorRecordExecutionObservationMutation$data;
  variables: OperatorRecordExecutionObservationMutation$variables;
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
    "concreteType": "RecordExecutionObservationPayload",
    "kind": "LinkedField",
    "name": "recordExecutionObservation",
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
        "concreteType": "OperatorCommandExecutionObservation",
        "kind": "LinkedField",
        "name": "observation",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "normalizedStatus",
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
    "name": "OperatorRecordExecutionObservationMutation",
    "selections": (v2/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "OperatorRecordExecutionObservationMutation",
    "selections": (v2/*:: as any*/)
  },
  "params": {
    "cacheID": "59b95260b8b75cd60f29c526538ea38b",
    "id": null,
    "metadata": {},
    "name": "OperatorRecordExecutionObservationMutation",
    "operationKind": "mutation",
    "text": "mutation OperatorRecordExecutionObservationMutation(\n  $input: RecordExecutionObservationInput!\n) {\n  recordExecutionObservation(input: $input) {\n    command\n    operationId\n    affectedIds {\n      type\n      id\n    }\n    observation {\n      id\n      normalizedStatus\n    }\n    run {\n      id\n      executionState\n      verificationState\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "cf46350d20a13a3ffcab45cb6a024aa1";

export default node;
