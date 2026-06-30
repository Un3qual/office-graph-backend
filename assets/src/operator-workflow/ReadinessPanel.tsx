import { Panel, PanelRows } from "../ui/Panel";
import type { PacketReadiness } from "./api";
import {
  packetInputStatus,
  packetInputText
} from "./formatters";
import type { Loadable } from "./loadable";
import { listSummary } from "./presentation";
import { actionLabel, formatWorkflowStatus } from "./status";

type Props = {
  readiness: Loadable<PacketReadiness>;
};

export function ReadinessPanel({ readiness }: Props) {
  return (
    <Panel ariaLabel="Packet Readiness">
      <h2>Packet Readiness</h2>
      {readiness.state === "loading" ? <p>Loading readiness...</p> : null}
      {readiness.state === "idle" ? <p>No packet selected.</p> : null}
      {readiness.state === "error" ? <p className="error-text">{readiness.message}</p> : null}
      {readiness.state === "loaded" ? (
        <PanelRows
          rows={[
            ["Status", formatWorkflowStatus(readiness.data.status)],
            ["Objective", packetInputText(undefined)],
            ["Context", packetInputText(undefined)],
            ["Success criteria", packetInputText(undefined)],
            ["Autonomy", packetInputStatus(undefined)],
            [
              "Source references",
              listSummary(
                readiness.data.source_links.map((link) => link.title),
                2
              )
            ],
            ["Required", String(readiness.data.required_checks.length)],
            ["Blockers", readiness.data.blocker_reasons.join(", ") || "None"],
            ["Actions", readiness.data.allowed_next_actions.map(actionLabel).join(", ") || "None"]
          ]}
        />
      ) : null}
    </Panel>
  );
}
