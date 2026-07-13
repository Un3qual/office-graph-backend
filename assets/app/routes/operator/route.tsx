import { startTransition, useCallback, useState } from "react";
import { useSearchParams } from "react-router";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { OperatorWorkflowRouteQuery } from "./data";
import {
  OperatorWorkspace,
  OperatorWorkspaceError,
  OperatorWorkspaceLoading,
} from "./OperatorWorkspace";
import type { OperatorInboxPage } from "./types";
import { defaultOperatorInboxPage, useOperatorWorkflow } from "./workflow";

type InboxNavigation = {
  page: OperatorInboxPage;
  previousCursors: Array<string | null>;
};

type OperatorRouteContentProps = {
  fetchKey: number;
  linkedRunId: string | null;
  navigation: InboxNavigation;
  onNextPage: (cursor: string) => void;
  onManualIntakeAuthoritativeChange: (normalizedEventId?: string) => void;
  onPreviousPage: () => void;
  onSelectItem: (id: string) => void;
  onRefresh: () => void;
  requestedSelectedId: string | null;
};

export const routeOwnedOperatorWorkflowQuery = OperatorWorkflowRouteQuery;

export default function OperatorRoute() {
  const [searchParams, setSearchParams] = useSearchParams();
  const linkedRunId = searchParams.get("runId")?.trim() || null;
  const [fetchKey, setFetchKey] = useState(0);
  const refresh = useCallback(() => startTransition(() => setFetchKey((key) => key + 1)), []);
  const [navigation, setNavigation] = useState<InboxNavigation>({
    page: defaultOperatorInboxPage,
    previousCursors: [],
  });
  const [requestedSelectedId, setRequestedSelectedId] = useState<string | null>(null);

  const leaveLinkedRun = () => {
    if (linkedRunId) {
      const nextSearchParams = new URLSearchParams(searchParams);
      nextSearchParams.delete("runId");
      setSearchParams(nextSearchParams, { replace: true });
    }
  };

  const handleManualIntakeAuthoritativeChange = (normalizedEventId?: string) => {
    if (normalizedEventId) {
      setRequestedSelectedId(normalizedEventId);
      leaveLinkedRun();
      setNavigation({
        page: defaultOperatorInboxPage,
        previousCursors: [],
      });
    }

    refresh();
  };

  const selectItem = (id: string) => {
    setRequestedSelectedId(id);
    leaveLinkedRun();
  };

  const loadNextPage = (nextCursor: string) => {
    setRequestedSelectedId(null);
    setNavigation(({ page, previousCursors }) => ({
      page: page.after === nextCursor ? page : { ...page, after: nextCursor },
      previousCursors:
        page.after === nextCursor ? previousCursors : [...previousCursors, page.after],
    }));
  };

  const loadPreviousPage = () => {
    setRequestedSelectedId(null);
    setNavigation(({ page, previousCursors }) => {
      if (previousCursors.length === 0) {
        return { page, previousCursors };
      }

      return {
        page: {
          ...page,
          after: previousCursors[previousCursors.length - 1] ?? null,
        },
        previousCursors: previousCursors.slice(0, -1),
      };
    });
  };

  return (
    <AsyncBoundary
      errorFallback={
        <OperatorWorkspaceError
          canPageBackward={navigation.previousCursors.length > 0}
          onRetry={refresh}
          onPreviousPage={loadPreviousPage}
        />
      }
      loadingFallback={<OperatorWorkspaceLoading />}
      resetKey={`operator:${navigation.page.after ?? "initial"}:${fetchKey}`}
    >
      <OperatorRouteContent
        fetchKey={fetchKey}
        linkedRunId={linkedRunId}
        navigation={navigation}
        onManualIntakeAuthoritativeChange={handleManualIntakeAuthoritativeChange}
        onNextPage={loadNextPage}
        onPreviousPage={loadPreviousPage}
        onSelectItem={selectItem}
        onRefresh={refresh}
        requestedSelectedId={requestedSelectedId}
      />
    </AsyncBoundary>
  );
}

function OperatorRouteContent({
  fetchKey,
  linkedRunId,
  navigation,
  onManualIntakeAuthoritativeChange,
  onNextPage,
  onPreviousPage,
  onSelectItem,
  onRefresh,
  requestedSelectedId,
}: OperatorRouteContentProps) {
  const workflow = useOperatorWorkflow({
    fetchKey,
    inboxPage: navigation.page,
    requestedSelectedId,
    selectionMode: linkedRunId ? "linked_run" : "inbox",
  });

  return (
    <OperatorWorkspace
      canPageBackward={navigation.previousCursors.length > 0}
      fetchKey={fetchKey}
      linkedRunId={linkedRunId}
      onManualIntakeAuthoritativeChange={onManualIntakeAuthoritativeChange}
      onNextPage={onNextPage}
      onPreviousPage={onPreviousPage}
      onSelectItem={onSelectItem}
      onRefresh={onRefresh}
      workflow={workflow}
    />
  );
}
