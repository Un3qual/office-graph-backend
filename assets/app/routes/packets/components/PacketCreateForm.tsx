import { useRef, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { CommandFormFeedback } from "../../../relay/CommandFormFeedback";
import { submissionIdentity } from "../../../relay/commandFormSupport";
import { useCreateWorkPacketCommand } from "../commandWorkflow";
import { PacketContractFields, packetContractInput } from "./PacketContractFields";

type Props = {
  readonly onCreated: (operationId: string) => void;
  readonly onRefresh: () => void;
};

export function PacketCreateForm({ onCreated, onRefresh }: Props) {
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const command = useCreateWorkPacketCommand((success) => {
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
      <form onSubmit={submit} ref={formRef}>
        <fieldset disabled={command.state.status === "pending"}>
          <PacketContractFields
            commandState={command.state}
            errorScope="packet-create"
            titleLabel="Packet title"
          />
          <Button type="submit" variant="primary">
            {command.state.status === "pending" ? "Creating packet" : "Create packet"}
          </Button>
        </fieldset>
        <CommandFormFeedback
          formRef={formRef}
          pendingMessage={
            command.state.status === "pending" ? "Creating the packet contract..." : null
          }
          state={command.state}
        />
        {command.state.status === "success" ? (
          <p className="packet-command-success" role="status">
            Packet created with immutable version {command.state.result.packetVersion.versionNumber}
            .
          </p>
        ) : null}
      </form>
    </section>
  );
}
