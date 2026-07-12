import { useRef, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { CommandFormFeedback } from "../../../relay/CommandFormFeedback";
import { submissionIdentity } from "../../../relay/commandFormSupport";
import { useCreateWorkPacketVersionCommand } from "../commandWorkflow";
import type { PacketWorkspaceDetail } from "../types";
import { PacketContractFields, packetContractInput } from "./PacketContractFields";

type Props = {
  readonly onRefresh: () => void;
  readonly workspace: PacketWorkspaceDetail;
};

export function PacketEditor({ onRefresh, workspace }: Props) {
  const attempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const command = useCreateWorkPacketVersionCommand(() => onRefresh());
  const version = workspace.currentVersion;

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const contract = packetContractInput(event.currentTarget);
    const input = {
      ...contract,
      packetId: workspace.packet.id,
      expectedCurrentVersionId: version.id
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <section aria-label="Packet version editor" className="packet-command-card">
      <header>
        <p className="eyebrow">Immutable edit</p>
        <h3>Create the next version</h3>
      </header>
      <form key={version.id} onSubmit={submit} ref={formRef}>
        <fieldset disabled={command.state.status === "pending"}>
          <PacketContractFields
            commandState={command.state}
            errorScope="packet-version"
            titleLabel="Version title"
            version={version}
          />
          <Button type="submit" variant="primary">
            {command.state.status === "pending" ? "Saving new version" : "Save new version"}
          </Button>
        </fieldset>
        <CommandFormFeedback
          formRef={formRef}
          pendingMessage={
            command.state.status === "pending" ? "Saving an immutable packet version..." : null
          }
          scope="packet-version"
          state={command.state}
        />
      </form>
    </section>
  );
}
