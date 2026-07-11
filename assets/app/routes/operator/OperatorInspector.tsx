import { startTransition, useCallback, useState } from "react";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { ReadinessPanel, ReadinessPanelError } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import { EvidenceCommandForm } from "./components/EvidenceCommandForm";
import { RunCommandForm } from "./components/RunCommandForm";
import { PacketCommandForm } from "./components/PacketCommandForm";
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
  onRefresh: () => void;
  runId: string | null;
  selectedId: string | null;
};

export function OperatorInspector({
  readiness,
  readinessInput,
  onRefresh,
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
          <ValidatedReadinessPanel input={readinessInput} onRefresh={onRefresh} />
        </AsyncBoundary>
      ) : (
        <ReadinessPanel
          onValidateReadiness={() => setValidationRequested(true)}
          readiness={readiness}
          readinessInput={readinessInput}
        />
      )}
      <RunStatePanels onRefresh={onRefresh} runId={runId} selectedId={selectedId} />
    </>
  );
}

function ValidatedReadinessPanel({ input, onRefresh }: { input: PacketReadinessInput; onRefresh: () => void }) {
  const readiness = useValidatedPacketReadiness(input);

  return <>
    <ReadinessPanel readiness={readiness} readinessInput={input} />
    <PacketCommandForm item={null} onRefresh={onRefresh} readiness={readiness} readinessInput={input} />
  </>;
}

function RunStatePanels({
  runId,
  onRefresh,
  selectedId
}: {
  runId: string | null;
  onRefresh: () => void;
  selectedId: string | null;
}) {
  const [fetchKey, setFetchKey] = useState(0);
  const refresh = useCallback(() => {
    startTransition(() => setFetchKey(key => key + 1));
    onRefresh();
  }, [onRefresh]);
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
      resetKey={`${selectedId ?? "none"}:run:${runId}:${fetchKey}`}
    >
      <LoadedRunStatePanels fetchKey={fetchKey} onRefresh={refresh} runId={runId} />
    </AsyncBoundary>
  );
}

function LoadedRunStatePanels({ fetchKey, onRefresh, runId }: { fetchKey: number; onRefresh: () => void; runId: string }) {
  const runState = useOperatorRunState(runId, fetchKey);
  const verification = verificationOutcomeFromRunState(runState);

  return (
    <>
      <RunPanel runId={runId} runState={runState} state="loaded" />
      <RunCommandForm onRefresh={onRefresh} runState={runState} />
      <VerificationPanel state="loaded" verification={verification} />
      <EvidenceCommandForm onRefresh={onRefresh} runState={runState} />
    </>
  );
}
