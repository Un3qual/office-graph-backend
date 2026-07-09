/**
 * @generated SignedSource<<c6879f7315a70c003e0d72eb55b0569b>>
 * @lightSyntaxTransform
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ConcreteRequest } from 'relay-runtime';
export type ExecutePacketRunVerificationInput = {
  acceptancePolicyBasis: string;
  authorityPosture: string;
  autonomyPosture: string;
  contextSummary: string;
  evidenceBody: string;
  evidenceClaim: string;
  evidenceResult: string;
  evidenceTitle: string;
  flowIdentity: string;
  freshnessState: string;
  normalizedStatus: string;
  objective: string;
  observationIdempotencyKey: string;
  observationRationale: string;
  observationSourceIdentity: string;
  observationSourceKind: string;
  observedStatus: string;
  packetTitle: string;
  reason: string;
  requirements: string;
  sourceGraphItemId: string;
  sourceSurface: string;
  successCriteria: string;
  trustBasis: string;
  verificationCheckId: string;
};
export type ExecutePacketRunVerificationMutation$variables = {
  input: ExecutePacketRunVerificationInput;
};
export type ExecutePacketRunVerificationMutation$data = {
  readonly executePacketRunVerification: {
    readonly evidenceItems: ReadonlyArray<{
      readonly candidateId: string | null | undefined;
      readonly id: string;
      readonly state: string;
      readonly workRunId: string | null | undefined;
    }>;
    readonly missingEvidence: ReadonlyArray<{
      readonly reason: string;
      readonly verificationCheckId: string;
    }>;
    readonly observations: ReadonlyArray<{
      readonly id: string;
      readonly normalizedStatus: string;
      readonly sourceIdentity: string;
      readonly sourceKind: string;
    }>;
    readonly packet: {
      readonly id: string;
      readonly state: string;
      readonly title: string;
    };
    readonly packetVersion: {
      readonly id: string;
      readonly lifecycleState: string;
      readonly objective: string;
      readonly versionNumber: number;
    };
    readonly requiredChecks: ReadonlyArray<{
      readonly id: string;
      readonly state: string;
      readonly verificationCheckId: string;
    }>;
    readonly run: {
      readonly aggregateState: string;
      readonly executionState: string;
      readonly id: string;
      readonly verificationState: string;
    };
    readonly verificationResults: ReadonlyArray<{
      readonly actorPrincipalId: string | null | undefined;
      readonly evidenceItemId: string | null | undefined;
      readonly id: string;
      readonly operationId: string | null | undefined;
      readonly policyBasis: string | null | undefined;
      readonly result: string;
      readonly targetGraphItemId: string | null | undefined;
      readonly workPacketVersionId: string | null | undefined;
      readonly workRunId: string | null | undefined;
    }>;
  };
};
export type ExecutePacketRunVerificationMutation = {
  response: ExecutePacketRunVerificationMutation$data;
  variables: ExecutePacketRunVerificationMutation$variables;
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
  "kind": "ScalarField",
  "name": "verificationCheckId",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "workRunId",
  "storageKey": null
},
v5 = [
  {
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "input",
        "variableName": "input"
      }
    ],
    "concreteType": "PacketRunSummary",
    "kind": "LinkedField",
    "name": "executePacketRunVerification",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunPacket",
        "kind": "LinkedField",
        "name": "packet",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "title",
            "storageKey": null
          },
          (v2/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunPacketVersion",
        "kind": "LinkedField",
        "name": "packetVersion",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "versionNumber",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "lifecycleState",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "objective",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunRun",
        "kind": "LinkedField",
        "name": "run",
        "plural": false,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "aggregateState",
            "storageKey": null
          },
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
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunRequiredCheck",
        "kind": "LinkedField",
        "name": "requiredChecks",
        "plural": true,
        "selections": [
          (v1/*:: as any*/),
          (v3/*:: as any*/),
          (v2/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunObservation",
        "kind": "LinkedField",
        "name": "observations",
        "plural": true,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "normalizedStatus",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "sourceKind",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "sourceIdentity",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunEvidenceItem",
        "kind": "LinkedField",
        "name": "evidenceItems",
        "plural": true,
        "selections": [
          (v1/*:: as any*/),
          (v2/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "candidateId",
            "storageKey": null
          },
          (v4/*:: as any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunVerificationResult",
        "kind": "LinkedField",
        "name": "verificationResults",
        "plural": true,
        "selections": [
          (v1/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "result",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "evidenceItemId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "operationId",
            "storageKey": null
          },
          (v4/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "workPacketVersionId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "actorPrincipalId",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "policyBasis",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "targetGraphItemId",
            "storageKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "PacketRunMissingEvidence",
        "kind": "LinkedField",
        "name": "missingEvidence",
        "plural": true,
        "selections": [
          (v3/*:: as any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "reason",
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
    "name": "ExecutePacketRunVerificationMutation",
    "selections": (v5/*:: as any*/),
    "type": "RootMutationType",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*:: as any*/),
    "kind": "Operation",
    "name": "ExecutePacketRunVerificationMutation",
    "selections": (v5/*:: as any*/)
  },
  "params": {
    "cacheID": "0006e6a21865d4bfd9889c4913107253",
    "id": null,
    "metadata": {},
    "name": "ExecutePacketRunVerificationMutation",
    "operationKind": "mutation",
    "text": "mutation ExecutePacketRunVerificationMutation(\n  $input: ExecutePacketRunVerificationInput!\n) {\n  executePacketRunVerification(input: $input) {\n    packet {\n      id\n      title\n      state\n    }\n    packetVersion {\n      id\n      versionNumber\n      lifecycleState\n      objective\n    }\n    run {\n      id\n      aggregateState\n      executionState\n      verificationState\n    }\n    requiredChecks {\n      id\n      verificationCheckId\n      state\n    }\n    observations {\n      id\n      normalizedStatus\n      sourceKind\n      sourceIdentity\n    }\n    evidenceItems {\n      id\n      state\n      candidateId\n      workRunId\n    }\n    verificationResults {\n      id\n      result\n      evidenceItemId\n      operationId\n      workRunId\n      workPacketVersionId\n      actorPrincipalId\n      policyBasis\n      targetGraphItemId\n    }\n    missingEvidence {\n      verificationCheckId\n      reason\n    }\n  }\n}\n"
  }
};
})();

(node as any).hash = "ca50433d8fb55e656203cf721a8758d1";

export default node;
