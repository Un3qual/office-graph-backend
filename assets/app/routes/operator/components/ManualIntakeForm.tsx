import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, manualReplayIdentity, submissionIdentity } from "../commandFormSupport";
import { useSubmitManualIntakeCommand } from "../commandWorkflow";

export function ManualIntakeForm({ onRefresh }: { onRefresh: () => void }) {
  const [body, setBody] = useState("");
  const [preparing, setPreparing] = useState(false);
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const command = useSubmitManualIntakeCommand(onRefresh);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const normalizedBody = body.trim();
    if (!normalizedBody) return;
    setPreparing(true);
    attempt.current = submissionIdentity(attempt.current, { body: normalizedBody });
    const replayIdentity = await manualReplayIdentity(normalizedBody);
    command.submit({
      body: normalizedBody,
      idempotencyKey: attempt.current.key,
      replayIdentity,
      sourceIdentity: "manual:operator-console"
    });
    setPreparing(false);
  };
  const pending = preparing || command.state.status === "pending";

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
