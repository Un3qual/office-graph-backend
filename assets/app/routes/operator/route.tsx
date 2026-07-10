import { useState } from "react";
import { AsyncBoundary } from "../../../src/ui/AsyncBoundary";
import { OperatorWorkflowRouteQuery } from "./data";
import {
  OperatorWorkspace,
  OperatorWorkspaceError,
  OperatorWorkspaceLoading
} from "./OperatorWorkspace";
import type { OperatorInboxPage } from "./types";
import { defaultOperatorInboxPage, useOperatorWorkflow } from "./workflow";

type InboxNavigation = {
  page: OperatorInboxPage;
  previousCursors: Array<string | null>;
};

type OperatorRouteContentProps = {
  navigation: InboxNavigation;
  onNextPage: (cursor: string) => void;
  onPreviousPage: () => void;
  onSelectItem: (id: string) => void;
  requestedSelectedId: string | null;
};

export const routeOwnedOperatorWorkflowQuery = OperatorWorkflowRouteQuery;

export default function OperatorRoute() {
  const [navigation, setNavigation] = useState<InboxNavigation>({
    page: defaultOperatorInboxPage,
    previousCursors: []
  });
  const [requestedSelectedId, setRequestedSelectedId] = useState<string | null>(null);

  const loadNextPage = (nextCursor: string) => {
    setRequestedSelectedId(null);
    setNavigation(({ page, previousCursors }) => ({
      page: page.after === nextCursor ? page : { ...page, after: nextCursor },
      previousCursors:
        page.after === nextCursor ? previousCursors : [...previousCursors, page.after]
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
          after: previousCursors[previousCursors.length - 1] ?? null
        },
        previousCursors: previousCursors.slice(0, -1)
      };
    });
  };

  return (
    <AsyncBoundary
      errorFallback={
        <OperatorWorkspaceError
          canPageBackward={navigation.previousCursors.length > 0}
          onPreviousPage={loadPreviousPage}
        />
      }
      loadingFallback={<OperatorWorkspaceLoading />}
      resetKey={`operator:${navigation.page.after ?? "initial"}`}
    >
      <OperatorRouteContent
        navigation={navigation}
        onNextPage={loadNextPage}
        onPreviousPage={loadPreviousPage}
        onSelectItem={setRequestedSelectedId}
        requestedSelectedId={requestedSelectedId}
      />
    </AsyncBoundary>
  );
}

function OperatorRouteContent({
  navigation,
  onNextPage,
  onPreviousPage,
  onSelectItem,
  requestedSelectedId
}: OperatorRouteContentProps) {
  const workflow = useOperatorWorkflow({
    inboxPage: navigation.page,
    requestedSelectedId
  });

  return (
    <OperatorWorkspace
      canPageBackward={navigation.previousCursors.length > 0}
      onNextPage={onNextPage}
      onPreviousPage={onPreviousPage}
      onSelectItem={onSelectItem}
      workflow={workflow}
    />
  );
}
