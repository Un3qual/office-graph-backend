import { useState } from "react";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { ReadinessPanel, ReadinessPanelError } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import { verificationOutcomeFromRunState } from "./derived";
import type { PacketReadinessInput } from "./types";
import {
  type PacketReadinessState,
  useOperatorRunState,
  useValidatedPacketReadiness
} from "./workflow";

type Props = {
  readiness: PacketReadinessState | null;
  readinessInput: PacketReadinessInput | null;
  runId: string | null;
  selectedId: string | null;
};

export function OperatorInspector({
  readiness,
  readinessInput,
  runId,
  selectedId
}: Props) {
  const [validationRequested, setValidationRequested] = useState(false);

  return (
    <>
      {validationRequested && readiness && readinessInput ? (
        <AsyncBoundary
          errorFallback={<ReadinessPanelError />}
          loadingFallback={
            <ReadinessPanel
              isValidating
              readiness={readiness}
              readinessInput={readinessInput}
            />
          }
          resetKey={`${selectedId ?? "none"}:readiness:requested`}
        >
          <ValidatedReadinessPanel input={readinessInput} />
        </AsyncBoundary>
      ) : (
        <ReadinessPanel
          onValidateReadiness={() => setValidationRequested(true)}
          readiness={readiness}
          readinessInput={readinessInput}
        />
      )}
      <RunStatePanels runId={runId} selectedId={selectedId} />
    </>
  );
}

function ValidatedReadinessPanel({ input }: { input: PacketReadinessInput }) {
  const readiness = useValidatedPacketReadiness(input);

  return <ReadinessPanel readiness={readiness} readinessInput={input} />;
}

function RunStatePanels({
  runId,
  selectedId
}: {
  runId: string | null;
  selectedId: string | null;
}) {
  if (!runId) {
    return (
      <>
        <RunPanel runId={null} runState={null} state="empty" />
        <VerificationPanel state="empty" verification={null} />
      </>
    );
  }

  return (
    <AsyncBoundary
      errorFallback={
        <>
          <RunPanel runId={runId} runState={null} state="error" />
          <VerificationPanel state="error" verification={null} />
        </>
      }
      loadingFallback={
        <>
          <RunPanel runId={runId} runState={null} state="loading" />
          <VerificationPanel state="loading" verification={null} />
        </>
      }
      resetKey={`${selectedId ?? "none"}:run:${runId}`}
    >
      <LoadedRunStatePanels runId={runId} />
    </AsyncBoundary>
  );
}

function LoadedRunStatePanels({ runId }: { runId: string }) {
  const runState = useOperatorRunState(runId);
  const verification = verificationOutcomeFromRunState(runState);

  return (
    <>
      <RunPanel runId={runId} runState={runState} state="loaded" />
      <VerificationPanel state="loaded" verification={verification} />
    </>
  );
}
