import { useRef, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { CommandFieldError, CommandFormFeedback } from "../../../relay/CommandFormFeedback";
import {
  commandFieldErrorProps,
  defaultValue,
  enabledAffordance,
  submissionIdentity
} from "../../../relay/commandFormSupport";
import { useStartWorkRunCommand } from "../commandWorkflow";
import type { PacketWorkspaceDetail } from "../types";

type Props = {
  readonly onRefresh: () => void;
  readonly workspace: PacketWorkspaceDetail;
};

export function PacketRunForm({ onRefresh, workspace }: Props) {
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const command = useStartWorkRunCommand(success => {
    if (success) {
      attempt.current = null;
    }
    onRefresh();
  });
  const visibleAffordance = workspace.commandAffordances.find(
    affordance => affordance.identity === "start_work_run"
  );
  const affordance = enabledAffordance(workspace.commandAffordances, "start_work_run");

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!affordance) {
      return;
    }

    const data = new FormData(event.currentTarget);
    const input = {
      packetVersionId: defaultValue(affordance, "packet_version_id"),
      sourceSurface: String(data.get("sourceSurface") ?? "").trim(),
      reason: String(data.get("reason") ?? "").trim(),
      authorityPosture: String(data.get("authorityPosture") ?? "").trim()
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <section aria-label="Run start" className="packet-command-card">
      <header>
        <p className="eyebrow">Current readiness</p>
        <h3>{workspace.ready ? "Ready for a run" : "Run start blocked"}</h3>
      </header>
      {visibleAffordance ? <p>{visibleAffordance.safeExplanation}</p> : null}
      {workspace.blockerReasons.length > 0 ? (
        <ul className="packet-blocker-list">
          {workspace.blockerReasons.map(blocker => <li key={blocker}>{blocker}</li>)}
        </ul>
      ) : null}
      {affordance ? (
        <form onSubmit={submit} ref={formRef}>
          <fieldset disabled={command.state.status === "pending"}>
            <label>
              Source surface
              <input
                {...commandFieldErrorProps(command.state, "packet-run", "sourceSurface")}
                defaultValue={defaultValue(affordance, "source_surface")}
                name="sourceSurface"
                required
              />
              <CommandFieldError controlName="sourceSurface" scope="packet-run" state={command.state} />
            </label>
            <label>
              Reason
              <textarea
                {...commandFieldErrorProps(command.state, "packet-run", "reason")}
                defaultValue={defaultValue(affordance, "reason")}
                name="reason"
                required
              />
              <CommandFieldError controlName="reason" scope="packet-run" state={command.state} />
            </label>
            <label>
              Authority posture
              <input
                {...commandFieldErrorProps(command.state, "packet-run", "authorityPosture")}
                defaultValue={defaultValue(affordance, "authority_posture")}
                name="authorityPosture"
                required
              />
              <CommandFieldError controlName="authorityPosture" scope="packet-run" state={command.state} />
            </label>
            <Button type="submit" variant="primary">
              {command.state.status === "pending" ? "Starting work run" : "Start work run"}
            </Button>
          </fieldset>
          <CommandFormFeedback
            formRef={formRef}
            pendingMessage={command.state.status === "pending" ? "Starting the work run..." : null}
            scope="packet-run"
            state={command.state}
          />
        </form>
      ) : null}
      {command.state.status === "success" ? (
        <section aria-label="Run result" className="packet-run-result">
          <p>
            Execution {command.state.result.run.executionState}; verification {command.state.result.run.verificationState}.
          </p>
          <a href={`/operator?runId=${encodeURIComponent(command.state.result.run.id)}`}>
            Open run {command.state.result.run.id}
          </a>
        </section>
      ) : null}
    </section>
  );
}
