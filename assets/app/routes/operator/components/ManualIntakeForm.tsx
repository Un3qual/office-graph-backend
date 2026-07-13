import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { CommandFieldError, CommandFormFeedback } from "../../../relay/CommandFormFeedback";
import {
  commandFieldErrorProps,
  manualReplayIdentity,
  submissionIdentity,
} from "../commandFormSupport";
import { useSubmitManualIntakeCommand } from "../commandWorkflow";

export function ManualIntakeForm({
  onAuthoritativeChange,
}: {
  onAuthoritativeChange: (normalizedEventId?: string) => void;
}) {
  const [body, setBody] = useState("");
  const [preparing, setPreparing] = useState(false);
  const [preparationError, setPreparationError] = useState<string | null>(null);
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const command = useSubmitManualIntakeCommand((success) =>
    onAuthoritativeChange(success?.result.normalizedEventId),
  );

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const normalizedBody = body.trim();
    if (!normalizedBody) return;
    setPreparing(true);
    setPreparationError(null);
    try {
      attempt.current = submissionIdentity(attempt.current, { body: normalizedBody });
      const replayIdentity = await manualReplayIdentity(normalizedBody);
      command.submit({
        body: normalizedBody,
        idempotencyKey: attempt.current.key,
        replayIdentity,
        sourceIdentity: "manual:operator-console",
      });
    } catch (_error) {
      setPreparationError("Unable to prepare manual intake. Try again.");
    } finally {
      setPreparing(false);
    }
  };
  const pending = preparing || command.state.status === "pending";

  return (
    <form className="operator-command-form operator-intake-form" onSubmit={submit} ref={formRef}>
      <label htmlFor="manual-intake">Manual intake</label>
      <textarea
        {...commandFieldErrorProps(command.state, "manual-intake", "body")}
        id="manual-intake"
        name="body"
        onChange={(event) => setBody(event.target.value)}
        rows={3}
        value={body}
      />
      <CommandFieldError controlName="body" scope="manual-intake" state={command.state} />
      <Button isDisabled={pending || body.trim() === ""} type="submit" variant="primary">
        {pending ? "Submitting intake" : "Submit intake"}
      </Button>
      {preparationError ? (
        <p className="ui-form-feedback" data-kind="error" role="alert">
          {preparationError}
        </p>
      ) : (
        <CommandFormFeedback
          formRef={formRef}
          pendingMessage={pending ? "Submitting intake..." : null}
          state={command.state}
        />
      )}
    </form>
  );
}
