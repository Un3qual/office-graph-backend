import { Badge } from "../../../../src/ui/Badge";
import { Panel } from "../../../../src/ui/Panel";
import { formatLabel, statusTone } from "../presentation";
import type { OperatorRunConversation } from "../workflow";
import {
  AgentConversationForm,
  AgentExecutionAction,
  AgentInvocationForm,
  ApprovalDecisionForm,
  ContextExpansionDecisionForm,
} from "./AgentCommandForms";

export function AgentActivityPanel({
  activity,
  onRefresh,
}: {
  activity: OperatorRunConversation;
  onRefresh: () => void;
}) {
  return (
    <Panel ariaLabel="Agent Activity">
      <h2>Agent Activity</h2>
      <AgentInvocationForm activity={activity} onRefresh={onRefresh} />
      <AgentConversationForm activity={activity} onRefresh={onRefresh} />
      <ActivityList activity={activity} onRefresh={onRefresh} />
    </Panel>
  );
}

function ActivityList({
  activity,
  onRefresh,
}: {
  activity: OperatorRunConversation;
  onRefresh: () => void;
}) {
  return (
    <div className="agent-activity-sections">
      <section aria-label="Agent executions">
        <h3>Executions</h3>
        {activity.executions.length === 0 ? <p>No agent executions yet.</p> : null}
        {activity.executions.map((execution) => (
          <article className="agent-activity-card" key={execution.id}>
            <Badge tone={statusTone(execution.state)}>{execution.state}</Badge>
            <p>{execution.requestedOutcome}</p>
            {execution.failureCode ? <p>Failure: {formatLabel(execution.failureCode)}</p> : null}
            <AgentExecutionAction
              affordances={activity.commandAffordances}
              execution={execution}
              onRefresh={onRefresh}
            />
          </article>
        ))}
      </section>

      <section aria-label="Run conversation messages">
        <h3>Conversation</h3>
        {activity.messages.length === 0 ? <p>No messages yet.</p> : null}
        {activity.messages.map((message) => (
          <article className="agent-activity-card" key={message.id}>
            <p>
              <strong>{formatLabel(message.source)}</strong> · {message.body}
            </p>
            {message.referencedContext?.entries.map((entry) => (
              <p className="agent-context-note" key={`${entry.posture}:${entry.rationaleCode}`}>
                {entry.posture} · {entry.rationaleCode}
              </p>
            ))}
          </article>
        ))}
      </section>

      <section aria-label="Agent approval requests">
        <h3>Approvals</h3>
        {activity.approvalRequests.length === 0 ? <p>No approval requests.</p> : null}
        {activity.approvalRequests.map((request) => (
          <article className="agent-activity-card" key={request.id}>
            <h4>Approval: {request.requestedAction}</h4>
            <p>{request.reason}</p>
            <ApprovalDecisionForm
              affordances={activity.commandAffordances}
              onRefresh={onRefresh}
              request={request}
            />
          </article>
        ))}
      </section>

      <section aria-label="Agent context expansion requests">
        <h3>Context expansion</h3>
        {activity.contextExpansionRequests.length === 0 ? (
          <p>No context expansion requests.</p>
        ) : null}
        {activity.contextExpansionRequests.map((request) => (
          <article className="agent-activity-card" key={request.id}>
            <h4>Context expansion: {request.targetResourceType}</h4>
            <p>{request.reason}</p>
            <ContextExpansionDecisionForm
              affordances={activity.commandAffordances}
              onRefresh={onRefresh}
              request={request}
            />
          </article>
        ))}
      </section>
    </div>
  );
}
