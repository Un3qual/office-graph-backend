import { useEffect, useState } from "react";
import type {
  OperatorInbox,
  OperatorRunState,
  OperatorWorkflowItem,
  PacketReadiness,
  VerificationOutcome
} from "./api";
import { errorMessage, type Loadable } from "./loadable";
import type { OperatorWorkflowProjectionClient } from "./projectionClient";

export function useOperatorWorkflow(client: OperatorWorkflowProjectionClient) {
  const [inbox, setInbox] = useState<Loadable<OperatorInbox>>({ state: "loading" });
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [item, setItem] = useState<Loadable<OperatorWorkflowItem>>({ state: "idle" });
  const [readiness, setReadiness] = useState<Loadable<PacketReadiness>>({ state: "idle" });
  const [runState, setRunState] = useState<Loadable<OperatorRunState>>({ state: "idle" });
  const [verification, setVerification] = useState<Loadable<VerificationOutcome>>({
    state: "idle"
  });

  useEffect(() => {
    let cancelled = false;

    setInbox({ state: "loading" });
    client
      .loadInbox()
      .then((nextInbox) => {
        if (cancelled) {
          return;
        }

        setInbox({ state: "loaded", data: nextInbox });
        setSelectedId(nextInbox.rows[0]?.normalized_event_id ?? null);
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setInbox({ state: "error", message: errorMessage(error) });
        }
      });

    return () => {
      cancelled = true;
    };
  }, [client]);

  useEffect(() => {
    if (!selectedId) {
      setItem({ state: "idle" });
      setReadiness({ state: "idle" });
      setRunState({ state: "idle" });
      setVerification({ state: "idle" });
      return;
    }

    let cancelled = false;

    setItem({ state: "loading" });
    setReadiness({ state: "idle" });
    setRunState({ state: "idle" });
    setVerification({ state: "idle" });

    client
      .loadItem(selectedId)
      .then((nextItem) => {
        if (cancelled) {
          return;
        }

        setItem({ state: "loaded", data: nextItem });
        loadReadiness(client, nextItem, setReadiness, () => cancelled);
        loadRun(client, nextItem, setRunState, setVerification, () => cancelled);
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setItem({ state: "error", message: errorMessage(error) });
        }
      });

    return () => {
      cancelled = true;
    };
  }, [client, selectedId]);

  return {
    inbox,
    item,
    readiness,
    rows: inbox.state === "loaded" ? inbox.data.rows : [],
    runState,
    selectedId,
    selectedItem: item.state === "loaded" ? item.data : null,
    selectItem: setSelectedId,
    verification
  };
}

function loadReadiness(
  client: OperatorWorkflowProjectionClient,
  item: OperatorWorkflowItem,
  setReadiness: (state: Loadable<PacketReadiness>) => void,
  isCancelled: () => boolean
) {
  setReadiness({ state: "loading" });
  client
    .loadPacketReadinessForItem(item)
    .then((data) => {
      if (!isCancelled()) {
        setReadiness({ state: "loaded", data });
      }
    })
    .catch((error: unknown) => {
      if (!isCancelled()) {
        setReadiness({ state: "error", message: errorMessage(error) });
      }
    });
}

function loadRun(
  client: OperatorWorkflowProjectionClient,
  item: OperatorWorkflowItem,
  setRunState: (state: Loadable<OperatorRunState>) => void,
  setVerification: (state: Loadable<VerificationOutcome>) => void,
  isCancelled: () => boolean
) {
  setRunState({ state: "loading" });
  setVerification({ state: "loading" });

  client
    .loadRunStateForItem(item)
    .then((data) => {
      if (!isCancelled()) {
        setRunState(data ? { state: "loaded", data } : { state: "idle" });
      }
    })
    .catch((error: unknown) => {
      if (!isCancelled()) {
        setRunState({ state: "error", message: errorMessage(error) });
      }
    });

  client
    .loadVerificationOutcomeForItem(item)
    .then((data) => {
      if (!isCancelled()) {
        setVerification(data ? { state: "loaded", data } : { state: "idle" });
      }
    })
    .catch((error: unknown) => {
      if (!isCancelled()) {
        setVerification({ state: "error", message: errorMessage(error) });
      }
    });
}
