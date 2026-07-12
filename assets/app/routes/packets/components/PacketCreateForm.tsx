import { useRef, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, submissionIdentity } from "../../../relay/commandFormSupport";
import { useCreateWorkPacketCommand } from "../commandWorkflow";
import { PacketContractFields, packetContractInput } from "./PacketContractFields";

type Props = {
  readonly onCreated: (operationId: string) => void;
  readonly onRefresh: () => void;
};

export function PacketCreateForm({ onCreated, onRefresh }: Props) {
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const command = useCreateWorkPacketCommand(success => {
    if (success) {
      attempt.current = null;
      onCreated(success.operationId);
    }
    onRefresh();
  });

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const input = packetContractInput(event.currentTarget);
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <section aria-label="Create packet" className="packet-command-card">
      <header>
        <p className="eyebrow">New contract</p>
        <h2>Create packet</h2>
      </header>
      <form onSubmit={submit}>
        <fieldset disabled={command.state.status === "pending"}>
          <PacketContractFields titleLabel="Packet title" />
          <Button type="submit" variant="primary">
            {command.state.status === "pending" ? "Creating packet" : "Create packet"}
          </Button>
        </fieldset>
        <FormFeedback
          feedback={commandFeedback(command.state)}
          pendingMessage={
            command.state.status === "pending" ? "Creating the packet contract..." : null
          }
        />
        {command.state.status === "success" ? (
          <p className="packet-command-success" role="status">
            Packet created with immutable version {command.state.result.packetVersion.versionNumber}.
          </p>
        ) : null}
      </form>
    </section>
  );
}
