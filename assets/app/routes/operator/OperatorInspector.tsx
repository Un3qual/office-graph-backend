import { startTransition, useCallback, useState } from "react";
import { readInlineData, useLazyLoadQuery } from "react-relay";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { Button } from "../../../src/ui/Button";
import { ReadinessPanel, ReadinessPanelError } from "./components/ReadinessPanel";
import { RunPanel } from "./components/RunPanel";
import { VerificationPanel } from "./components/VerificationPanel";
import { EvidenceCommandForm } from "./components/EvidenceCommandForm";
import { RunCommandForm } from "./components/RunCommandForm";
import { PacketCommandForm } from "./components/PacketCommandForm";
import {
  OperatorRunCommandOptionPageConnectionFragment,
  OperatorRunCommandOptionPageQuery,
} from "./data";
import type {
  OperatorRunCommandOptionPageConnectionFragment$data,
  OperatorRunCommandOptionPageConnectionFragment$key,
} from "../../relay/__generated__/OperatorRunCommandOptionPageConnectionFragment.graphql";
import type { OperatorRunCommandOptionPageQuery as OperatorRunCommandOptionPageOperation } from "../../relay/__generated__/OperatorRunCommandOptionPageQuery.graphql";
import { verificationOutcomeFromRunState } from "./derived";
import type { PacketReadinessInput } from "./types";
import {
  type PacketReadinessState,
  type OperatorRunState,
  useOperatorRunState,
  useValidatedPacketReadiness,
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
  selectedId,
}: Props) {
  const [validationRequested, setValidationRequested] = useState(false);

  return (
    <>
      {validationRequested && readiness && readinessInput ? (
        <AsyncBoundary
          errorFallback={<ReadinessPanelError onRetry={onRefresh} />}
          loadingFallback={
            <ReadinessPanel isValidating readiness={readiness} readinessInput={readinessInput} />
          }
          resetKey={`${selectedId ?? "none"}:readiness:requested:${fetchKey}`}
        >
          <ValidatedReadinessPanel
            fetchKey={fetchKey}
            input={readinessInput}
            onRefresh={onRefresh}
          />
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

function ValidatedReadinessPanel({
  fetchKey,
  input,
  onRefresh,
}: {
  fetchKey: number;
  input: PacketReadinessInput;
  onRefresh: () => void;
}) {
  const readiness = useValidatedPacketReadiness(input, fetchKey);

  return (
    <>
      <ReadinessPanel readiness={readiness} readinessInput={input} />
      <PacketCommandForm
        item={null}
        onRefresh={onRefresh}
        readiness={readiness}
        readinessInput={input}
      />
    </>
  );
}

function RunStatePanels({
  runId,
  onRefresh,
  selectedId,
}: {
  runId: string | null;
  onRefresh: () => void;
  selectedId: string | null;
}) {
  const [fetchKey, setFetchKey] = useState(0);
  const refresh = useCallback(() => {
    startTransition(() => setFetchKey((key) => key + 1));
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

function LoadedRunStatePanels({
  fetchKey,
  onRefresh,
  runId,
}: {
  fetchKey: number;
  onRefresh: () => void;
  runId: string;
}) {
  const [activityCursors, setActivityCursors] = useState<Array<string | null>>([null]);
  const activityAfter = activityCursors.at(-1) ?? null;
  const runState = useOperatorRunState(runId, fetchKey, activityAfter);
  const verification = verificationOutcomeFromRunState(runState);

  return (
    <>
      <RunPanel
        onNextActivityPage={() => {
          const cursor = runState.activity?.pageInfo.endCursor;
          if (cursor) setActivityCursors((cursors) => [...cursors, cursor]);
        }}
        onPreviousActivityPage={() =>
          setActivityCursors((cursors) => (cursors.length > 1 ? cursors.slice(0, -1) : cursors))
        }
        runId={runId}
        runState={runState}
        state="loaded"
      />
      {runState.commandOptionsOverflow ? (
        <PagedCommandForms key={runId} onRefresh={onRefresh} runId={runId} runState={runState} />
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
  runState,
}: {
  onRefresh: () => void;
  runId: string;
  runState: OperatorRunState;
}) {
  const [cursors, setCursors] = useState<Record<CommandOptionKind, Array<string | null>>>({
    observation: [null],
    evidenceCandidate: [null],
    evidenceAcceptance: [null],
    waiver: [null],
  });
  const summary = runState.commandOptionSummary;
  const overflow = {
    observation: summary.observation > 20,
    evidenceCandidate: summary.evidenceCandidate > 20,
    evidenceAcceptance: summary.evidenceAcceptance > 20,
    waiver: summary.waiver > 20,
  };
  const data = useLazyLoadQuery<OperatorRunCommandOptionPageOperation>(
    OperatorRunCommandOptionPageQuery,
    {
      id: runId,
      first: 20,
      observationAfter: cursors.observation.at(-1) ?? null,
      evidenceCandidateAfter: cursors.evidenceCandidate.at(-1) ?? null,
      evidenceAcceptanceAfter: cursors.evidenceAcceptance.at(-1) ?? null,
      waiverAfter: cursors.waiver.at(-1) ?? null,
      loadObservation: overflow.observation,
      loadEvidenceCandidate: overflow.evidenceCandidate,
      loadEvidenceAcceptance: overflow.evidenceAcceptance,
      loadWaiver: overflow.waiver,
    },
    { fetchPolicy: "network-only" },
  );
  const page = <K extends keyof typeof cursors>(
    key: K,
    connection: OptionConnection | null | undefined,
  ) => ({
    ...commandOptionPageData(connection),
    options: commandOptionPageData(connection).options,
    hasNext: commandOptionPageData(connection).hasNext,
    hasPrevious: commandOptionPageData(connection).hasPrevious,
    next: () => {
      const cursor = commandOptionPageData(connection).endCursor;
      if (cursor) setCursors((current) => ({ ...current, [key]: [...current[key], cursor] }));
    },
    previous: () =>
      setCursors((current) => ({
        ...current,
        [key]: current[key].length > 1 ? current[key].slice(0, -1) : current[key],
      })),
  });
  const observation = page("observation", data.observation);
  const evidenceCandidate = page("evidenceCandidate", data.evidenceCandidate);
  const evidenceAcceptance = page("evidenceAcceptance", data.evidenceAcceptance);
  const waiver = page("waiver", data.waiver);
  const pagedRunState: OperatorRunState = {
    ...runState,
    commandOptions: {
      observation: overflow.observation
        ? observation.options.flatMap((choice) => (choice.observation ? [choice.observation] : []))
        : runState.commandOptions.observation,
      evidenceCandidate: overflow.evidenceCandidate
        ? evidenceCandidate.options.flatMap((choice) =>
            choice.evidenceCandidate ? [choice.evidenceCandidate] : [],
          )
        : runState.commandOptions.evidenceCandidate,
      evidenceAcceptance: overflow.evidenceAcceptance
        ? evidenceAcceptance.options.flatMap((choice) =>
            choice.evidenceAcceptance ? [choice.evidenceAcceptance] : [],
          )
        : runState.commandOptions.evidenceAcceptance,
      waiver: overflow.waiver
        ? waiver.options.flatMap((choice) => (choice.waiver ? [choice.waiver] : []))
        : runState.commandOptions.waiver,
    },
  };

  return (
    <>
      <RunCommandForm onRefresh={onRefresh} runState={pagedRunState} />
      {overflow.observation ? (
        <ChoicePagination label="observation choices" page={observation} />
      ) : null}
      <EvidenceCommandForm onRefresh={onRefresh} runState={pagedRunState} />
      {overflow.evidenceCandidate ? (
        <ChoicePagination label="suggested evidence choices" page={evidenceCandidate} />
      ) : null}
      {overflow.evidenceAcceptance ? (
        <ChoicePagination label="evidence acceptance choices" page={evidenceAcceptance} />
      ) : null}
      {overflow.waiver ? <ChoicePagination label="waiver choices" page={waiver} /> : null}
    </>
  );
}

type CommandOptionKind = "observation" | "evidenceCandidate" | "evidenceAcceptance" | "waiver";
type OptionConnection = NonNullable<
  OperatorRunCommandOptionPageOperation["response"]["observation"]
>;
type ChoicePage = {
  hasNext: boolean;
  hasPrevious: boolean;
  next: () => void;
  previous: () => void;
};

function commandOptionPageData(connection: OptionConnection | null | undefined) {
  if (!connection) return { options: [], hasNext: false, hasPrevious: false, endCursor: null };
  const data: OperatorRunCommandOptionPageConnectionFragment$data =
    readInlineData<OperatorRunCommandOptionPageConnectionFragment$key>(
      OperatorRunCommandOptionPageConnectionFragment,
      connection,
    );
  return {
    options: (data.edges ?? []).flatMap((edge) => (edge?.node ? [edge.node] : [])),
    hasNext: data.pageInfo.hasNextPage,
    hasPrevious: data.pageInfo.hasPreviousPage,
    endCursor: data.pageInfo.endCursor,
  };
}

function ChoicePagination({ label, page }: { label: string; page: ChoicePage }) {
  return (
    <div aria-label={`${label} pagination`}>
      {page.hasPrevious ? <Button onPress={page.previous}>Previous {label}</Button> : null}
      {page.hasNext ? <Button onPress={page.next}>Next {label}</Button> : null}
    </div>
  );
}
