import { startTransition, useCallback, useState } from "react";
import { useLazyLoadQuery } from "react-relay";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { Button } from "../../../src/ui/Button";
import { ReadinessPanel, ReadinessPanelError } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import { EvidenceCommandForm } from "./components/EvidenceCommandForm";
import { RunCommandForm } from "./components/RunCommandForm";
import { PacketCommandForm } from "./components/PacketCommandForm";
import { OperatorRunCommandOptionPageQuery } from "./data";
import type { OperatorRunCommandOptionPageQuery as OperatorRunCommandOptionPageOperation } from "../../relay/__generated__/OperatorRunCommandOptionPageQuery.graphql";
import { verificationOutcomeFromRunState } from "./derived";
import type { PacketReadinessInput } from "./types";
import {
  type PacketReadinessState,
  type OperatorRunState,
  useOperatorRunState,
  useValidatedPacketReadiness
} from "./workflow";

type Props = {
  fetchKey: number;
  readiness: PacketReadinessState | null;
  readinessInput: PacketReadinessInput | null;
  onRefresh: () => void;
  runId: string | null;
  selectedId: string | null;
};

export function OperatorInspector({
  fetchKey,
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
          errorFallback={<ReadinessPanelError onRetry={onRefresh} />}
          loadingFallback={
            <ReadinessPanel
              isValidating
              readiness={readiness}
              readinessInput={readinessInput}
            />
          }
          resetKey={`${selectedId ?? "none"}:readiness:requested:${fetchKey}`}
        >
          <ValidatedReadinessPanel fetchKey={fetchKey} input={readinessInput} onRefresh={onRefresh} />
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

function ValidatedReadinessPanel({ fetchKey, input, onRefresh }: { fetchKey: number; input: PacketReadinessInput; onRefresh: () => void }) {
  const readiness = useValidatedPacketReadiness(input, fetchKey);

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
          <Button onPress={refresh}>Retry run state</Button>
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
      <LoadedRunStatePanels key={runId} fetchKey={fetchKey} onRefresh={refresh} runId={runId} />
    </AsyncBoundary>
  );
}

function LoadedRunStatePanels({ fetchKey, onRefresh, runId }: { fetchKey: number; onRefresh: () => void; runId: string }) {
  const [activityCursors, setActivityCursors] = useState<Array<string | null>>([null]);
  const activityAfter = activityCursors.at(-1) ?? null;
  const runState = useOperatorRunState(runId, fetchKey, activityAfter);
  const verification = verificationOutcomeFromRunState(runState);

  return (
    <>
      <RunPanel
        onNextActivityPage={() => {
          const cursor = runState.activity?.pageInfo.endCursor;
          if (cursor) setActivityCursors(cursors => [...cursors, cursor]);
        }}
        onPreviousActivityPage={() =>
          setActivityCursors(cursors => cursors.length > 1 ? cursors.slice(0, -1) : cursors)
        }
        runId={runId}
        runState={runState}
        state="loaded"
      />
      {runState.commandOptionsOverflow ? (
        <PagedCommandForms
          key={runId}
          onRefresh={onRefresh}
          runId={runId}
          runState={runState}
        />
      ) : (
        <>
          <RunCommandForm onRefresh={onRefresh} runState={runState} />
          <EvidenceCommandForm onRefresh={onRefresh} runState={runState} />
        </>
      )}
      <VerificationPanel state="loaded" verification={verification} />
    </>
  );
}

function PagedCommandForms({
  onRefresh,
  runId,
  runState
}: {
  onRefresh: () => void;
  runId: string;
  runState: OperatorRunState;
}) {
  const observation = useCommandOptionPage(runId, "observation");
  const evidenceCandidate = useCommandOptionPage(runId, "evidence_candidate");
  const evidenceAcceptance = useCommandOptionPage(runId, "evidence_acceptance");
  const waiver = useCommandOptionPage(runId, "waiver");
  const pagedRunState = {
    ...runState,
    commandOptions: {
      observation: observation.options.flatMap(choice => choice.observation ? [choice.observation] : []),
      evidenceCandidate: evidenceCandidate.options.flatMap(choice => choice.evidenceCandidate ? [choice.evidenceCandidate] : []),
      evidenceAcceptance: evidenceAcceptance.options.flatMap(choice => choice.evidenceAcceptance ? [choice.evidenceAcceptance] : []),
      waiver: waiver.options.flatMap(choice => choice.waiver ? [choice.waiver] : [])
    }
  } as OperatorRunState;

  return <>
    <RunCommandForm onRefresh={onRefresh} runState={pagedRunState} />
    <ChoicePagination label="observation choices" page={observation} />
    <EvidenceCommandForm onRefresh={onRefresh} runState={pagedRunState} />
    <ChoicePagination label="evidence candidate choices" page={evidenceCandidate} />
    <ChoicePagination label="evidence acceptance choices" page={evidenceAcceptance} />
    <ChoicePagination label="waiver choices" page={waiver} />
  </>;
}

function useCommandOptionPage(runId: string, kind: string) {
  const [cursors, setCursors] = useState<Array<string | null>>([null]);
  const after = cursors.at(-1) ?? null;
  const data = useLazyLoadQuery<OperatorRunCommandOptionPageOperation>(
    OperatorRunCommandOptionPageQuery,
    { id: runId, kind, first: 20, after },
    { fetchPolicy: "network-only" }
  );
  const connection = data.operatorRunState?.commandOptionPage;
  return {
    options: (connection?.edges ?? []).flatMap(edge => edge?.node ? [edge.node] : []),
    hasNext: connection?.pageInfo.hasNextPage ?? false,
    hasPrevious: connection?.pageInfo.hasPreviousPage ?? false,
    next: () => {
      const cursor = connection?.pageInfo.endCursor;
      if (cursor) setCursors(current => [...current, cursor]);
    },
    previous: () => setCursors(current => current.length > 1 ? current.slice(0, -1) : current)
  };
}

function ChoicePagination({ label, page }: { label: string; page: ReturnType<typeof useCommandOptionPage> }) {
  return <div aria-label={`${label} pagination`}>
    {page.hasPrevious ? <Button onPress={page.previous}>Previous {label}</Button> : null}
    {page.hasNext ? <Button onPress={page.next}>Next {label}</Button> : null}
  </div>;
}
