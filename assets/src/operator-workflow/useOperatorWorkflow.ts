import { useEffect, useState } from "react";
import type {
  OperatorInbox,
  OperatorRunState,
  OperatorWorkflowItem,
  PacketReadiness,
  VerificationOutcome
} from "./api";
import { errorMessage, type Loadable } from "./loadable";
import {
  packetReadinessForLoadedItem,
  runIdForItem,
  type OperatorWorkflowProjectionClient
} from "./projectionClient";

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

    const selectedInboxRow =
      inbox.state === "loaded"
        ? inbox.data.rows.find((row) => row.normalized_event_id === selectedId)
        : null;

    let cancelled = false;

    setItem({ state: "loading" });
    setReadiness({ state: "idle" });
    setRunState({ state: "idle" });
    setVerification({ state: "idle" });

    if (selectedInboxRow) {
      setItem({ state: "loaded", data: selectedInboxRow });
      loadOrReuseReadiness(client, selectedInboxRow, setReadiness, () => cancelled);
      loadRun(client, selectedInboxRow, setRunState, setVerification, () => cancelled);

      return () => {
        cancelled = true;
      };
    }

    client
      .loadItem(selectedId)
      .then((nextItem) => {
        if (cancelled) {
          return;
        }

        setItem({ state: "loaded", data: nextItem });
        loadOrReuseReadiness(client, nextItem, setReadiness, () => cancelled);
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
  }, [client, inbox, selectedId]);

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

function loadOrReuseReadiness(
  client: OperatorWorkflowProjectionClient,
  item: OperatorWorkflowItem,
  setReadiness: (state: Loadable<PacketReadiness>) => void,
  isCancelled: () => boolean
) {
  const loadedReadiness = packetReadinessForLoadedItem(item);

  if (loadedReadiness) {
    setReadiness({ state: "loaded", data: loadedReadiness });
    return;
  }

  loadReadiness(client, item, setReadiness, isCancelled);
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
  if (!runIdForItem(item)) {
    setRunState({ state: "idle" });
    setVerification({ state: "idle" });
    return;
  }

  setRunState({ state: "loading" });
  setVerification({ state: "loading" });

  client
    .loadRunStateForItem(item)
    .then((data) => {
      if (!isCancelled()) {
        setRunState(data ? { state: "loaded", data } : { state: "idle" });
        setVerification(
          data ? { state: "loaded", data: verificationOutcomeForRunState(data) } : { state: "idle" }
        );
      }
    })
    .catch((error: unknown) => {
      if (!isCancelled()) {
        const message = errorMessage(error);
        setRunState({ state: "error", message });
        setVerification({ state: "error", message });
      }
    });
}

function verificationOutcomeForRunState(runState: OperatorRunState): VerificationOutcome {
  return {
    type: "verification_outcome",
    status: runState.status,
    source_watermark: runState.source_watermark,
    run: runState.run,
    verification_results: runState.verification_results,
    missing_evidence: runState.missing_evidence
  };
}
