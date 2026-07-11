import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, manualReplayIdentity, submissionIdentity } from "../commandFormSupport";
import { useSubmitManualIntakeCommand } from "../commandWorkflow";

export function ManualIntakeForm({ onRefresh }: { onRefresh: () => void }) {
  const [body, setBody] = useState("");
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const command = useSubmitManualIntakeCommand(onRefresh);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const normalizedBody = body.trim();
    if (!normalizedBody) return;
    attempt.current = submissionIdentity(attempt.current, { body: normalizedBody });
    command.submit({
      body: normalizedBody,
      idempotencyKey: attempt.current.key,
      replayIdentity: manualReplayIdentity(normalizedBody),
      sourceIdentity: "manual:operator-console"
    });
  };
  const pending = command.state.status === "pending";

  return (
    <form className="operator-command-form operator-intake-form" onSubmit={submit}>
      <label htmlFor="manual-intake">Manual intake</label>
      <textarea id="manual-intake" onChange={event => setBody(event.target.value)} rows={3} value={body} />
      <Button isDisabled={pending || body.trim() === ""} type="submit" variant="primary">
        {pending ? "Submitting intake" : "Submit intake"}
      </Button>
      <FormFeedback feedback={commandFeedback(command.state)} pendingMessage={pending ? "Submitting intake..." : null} />
    </form>
  );
}
