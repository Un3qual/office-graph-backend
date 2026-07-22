import { useRef, useState, type FormEvent } from "react";
import { CommandFormFeedback } from "../../../relay/CommandFormFeedback";
import { Button } from "../../../../src/ui/Button";
import {
  defaultValue,
  defaultValues,
  enabledAffordance,
  submissionIdentity,
} from "../commandFormSupport";
import {
  useAppendConversationMessageCommand,
  useCancelAgentExecutionCommand,
  useInvokeAgentCommand,
  useResolveAgentApprovalCommand,
  useResolveAgentContextExpansionCommand,
  useStartRunConversationCommand,
} from "../commandWorkflow";
import type { OperatorRunConversation } from "../workflow";

type Affordances = OperatorRunConversation["commandAffordances"];
type Execution = OperatorRunConversation["executions"][number];
type ApprovalRequest = OperatorRunConversation["approvalRequests"][number];
type ExpansionRequest = OperatorRunConversation["contextExpansionRequests"][number];
type Attempt = { fingerprint: string; key: string } | null;

export function AgentInvocationForm({
  activity,
  onRefresh,
}: {
  activity: OperatorRunConversation;
  onRefresh: () => void;
}) {
  const affordance = enabledAffordance(activity.commandAffordances, "invoke_agent");
  const command = useInvokeAgentCommand(onRefresh);
  const attempt = useRef<Attempt>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const [outcome, setOutcome] = useState(
    affordance ? defaultValue(affordance, "requested_outcome") : "",
  );

  if (!affordance) return null;

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const input = {
      bindingId: defaultValue(affordance, "binding_id"),
      runId: defaultValue(affordance, "run_id"),
      graphItemId: defaultValue(affordance, "graph_item_id"),
      requestedOutcome: outcome.trim(),
      requestedCapabilities: defaultValues(affordance, "requested_capabilities"),
      autonomyMode: defaultValue(affordance, "autonomy_mode"),
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <form className="operator-command-form" onSubmit={submit} ref={formRef}>
      <label htmlFor="agent-requested-outcome">Requested outcome</label>
      <textarea
        id="agent-requested-outcome"
        name="requestedOutcome"
        onChange={(event) => setOutcome(event.target.value)}
        value={outcome}
      />
      <Button
        isDisabled={command.state.status === "pending" || !outcome.trim()}
        type="submit"
        variant="primary"
      >
        {command.state.status === "pending" ? "Invoking agent" : "Invoke agent"}
      </Button>
      <CommandFormFeedback formRef={formRef} state={command.state} />
    </form>
  );
}

export function AgentConversationForm({
  activity,
  onRefresh,
}: {
  activity: OperatorRunConversation;
  onRefresh: () => void;
}) {
  return activity.conversation ? (
    <MessageForm activity={activity} onRefresh={onRefresh} />
  ) : (
    <StartConversationForm activity={activity} onRefresh={onRefresh} />
  );
}

function StartConversationForm({
  activity,
  onRefresh,
}: {
  activity: OperatorRunConversation;
  onRefresh: () => void;
}) {
  const affordance = enabledAffordance(activity.commandAffordances, "start_run_conversation");
  const command = useStartRunConversationCommand(onRefresh);
  const attempt = useRef<Attempt>(null);
  const formRef = useRef<HTMLFormElement>(null);
  if (!affordance) return null;

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const input = {
      runId: defaultValue(affordance, "run_id"),
      graphItemId: defaultValue(affordance, "graph_item_id"),
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <form className="operator-command-form" onSubmit={submit} ref={formRef}>
      <p>Open a focused conversation for this run and graph item.</p>
      <Button isDisabled={command.state.status === "pending"} type="submit">
        {command.state.status === "pending" ? "Starting conversation" : "Start conversation"}
      </Button>
      <CommandFormFeedback formRef={formRef} state={command.state} />
    </form>
  );
}

function MessageForm({
  activity,
  onRefresh,
}: {
  activity: OperatorRunConversation;
  onRefresh: () => void;
}) {
  const command = useAppendConversationMessageCommand(onRefresh);
  const attempt = useRef<Attempt>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const [body, setBody] = useState("");
  const conversationId = activity.conversation?.id;
  if (!conversationId) return null;

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const input = {
      conversationId,
      body: body.trim(),
      contributionKind: "comment",
      proposedGraphChangeId: null,
      domainActionOperationId: null,
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <form className="operator-command-form" onSubmit={submit} ref={formRef}>
      <label htmlFor="agent-run-message">Run message</label>
      <textarea
        id="agent-run-message"
        name="body"
        onChange={(event) => setBody(event.target.value)}
        value={body}
      />
      <Button isDisabled={command.state.status === "pending" || !body.trim()} type="submit">
        {command.state.status === "pending" ? "Sending message" : "Send message"}
      </Button>
      <CommandFormFeedback formRef={formRef} state={command.state} />
    </form>
  );
}

export function AgentExecutionAction({
  affordances,
  execution,
  onRefresh,
}: {
  affordances: Affordances;
  execution: Execution;
  onRefresh: () => void;
}) {
  const affordance = enabledAffordance(affordances, "cancel_agent_execution");
  const command = useCancelAgentExecutionCommand(onRefresh);
  const attempt = useRef<Attempt>(null);
  const formRef = useRef<HTMLFormElement>(null);
  if (!affordance || ["cancelled", "completed", "failed"].includes(execution.state)) return null;

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const input = { executionId: execution.id, expectedStateVersion: execution.stateVersion };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <form onSubmit={submit} ref={formRef}>
      <Button isDisabled={command.state.status === "pending"} type="submit">
        {command.state.status === "pending"
          ? "Cancelling agent execution"
          : "Cancel agent execution"}
      </Button>
      <CommandFormFeedback formRef={formRef} state={command.state} />
    </form>
  );
}

export function ApprovalDecisionForm({
  affordances,
  onRefresh,
  request,
}: {
  affordances: Affordances;
  onRefresh: () => void;
  request: ApprovalRequest;
}) {
  const affordance = enabledAffordance(affordances, "resolve_agent_approval");
  const command = useResolveAgentApprovalCommand(onRefresh);
  const attempt = useRef<Attempt>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const [reason, setReason] = useState("");
  if (!affordance || request.state !== "pending") return null;

  const submit = (decision: string) => {
    const input = {
      approvalRequestId: request.id,
      expectedVersion: request.version,
      decision,
      resolutionReason: reason.trim(),
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <form className="agent-gate-form" onSubmit={(event) => event.preventDefault()} ref={formRef}>
      <label htmlFor={`approval-reason-${request.id}`}>Approval resolution reason</label>
      <textarea
        id={`approval-reason-${request.id}`}
        name="resolutionReason"
        onChange={(event) => setReason(event.target.value)}
        value={reason}
      />
      <div className="ui-panel-actions">
        <Button
          isDisabled={command.state.status === "pending" || !reason.trim()}
          onPress={() => submit("approved")}
        >
          Approve request
        </Button>
        <Button
          isDisabled={command.state.status === "pending" || !reason.trim()}
          onPress={() => submit("denied")}
        >
          Deny request
        </Button>
      </div>
      <CommandFormFeedback formRef={formRef} state={command.state} />
    </form>
  );
}

export function ContextExpansionDecisionForm({
  affordances,
  onRefresh,
  request,
}: {
  affordances: Affordances;
  onRefresh: () => void;
  request: ExpansionRequest;
}) {
  const affordance = enabledAffordance(affordances, "resolve_agent_context_expansion");
  const command = useResolveAgentContextExpansionCommand(onRefresh);
  const attempt = useRef<Attempt>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const [reason, setReason] = useState("");
  if (!affordance || request.state !== "pending") return null;

  const submit = (decision: string) => {
    const input = {
      contextExpansionRequestId: request.id,
      expectedVersion: request.version,
      decision,
      resolutionReason: reason.trim(),
    };
    attempt.current = submissionIdentity(attempt.current, input);
    command.submit({ ...input, idempotencyKey: attempt.current.key });
  };

  return (
    <form className="agent-gate-form" onSubmit={(event) => event.preventDefault()} ref={formRef}>
      <label htmlFor={`expansion-reason-${request.id}`}>Context expansion resolution reason</label>
      <textarea
        id={`expansion-reason-${request.id}`}
        name="resolutionReason"
        onChange={(event) => setReason(event.target.value)}
        value={reason}
      />
      <div className="ui-panel-actions">
        <Button
          isDisabled={command.state.status === "pending" || !reason.trim()}
          onPress={() => submit("approved")}
        >
          Approve context expansion
        </Button>
        <Button
          isDisabled={command.state.status === "pending" || !reason.trim()}
          onPress={() => submit("denied")}
        >
          Deny context expansion
        </Button>
      </div>
      <CommandFormFeedback formRef={formRef} state={command.state} />
    </form>
  );
}
