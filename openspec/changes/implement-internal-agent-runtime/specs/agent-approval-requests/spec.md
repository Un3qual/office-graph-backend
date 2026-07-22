## ADDED Requirements

### Requirement: Approval Requests Are Durable And Step Scoped
Office Graph SHALL record approval requests with execution, step, requested
action, reason, scope, capability, credential/external-write posture, expiry,
authority snapshot, and operation.

#### Scenario: Step requires approval
- **WHEN** effective policy requires human approval before a model/tool/domain
  step
- **THEN** the execution MUST enter waiting-approval and create one replay-safe
  approval request

#### Scenario: Step lacks authority before approval

- **WHEN** a step requires approval but its manifest capability, credential,
  scope, sensitivity, timeout, or budget preconditions are not satisfied
- **THEN** the execution MUST fail closed before creating an approval request

#### Scenario: Approval is resolved
- **WHEN** an authorized actor approves or denies the current request
- **THEN** Office Graph MUST record the decision and operation, resume only the
  matching approved step, or terminate/downgrade the denied step

#### Scenario: Approval follows a context expansion
- **WHEN** a step obtains bounded context and subsequently requires human
  approval
- **THEN** the approval request and resume job MUST retain the exact expansion
  request and MUST revalidate both unexpired grants before adapter dispatch

#### Scenario: Stale approval is submitted
- **WHEN** a request is expired, cancelled, superseded, or no longer matches the
  waiting execution version
- **THEN** the resolution command MUST return a stable conflict and MUST NOT
  resume execution

#### Scenario: Waiting request expires without a decision
- **WHEN** an approval or context-expansion request reaches its expiry while its
  exact execution step is still waiting
- **THEN** Office Graph MUST durably mark the request expired and terminalize
  the waiting execution instead of leaving it stuck

#### Scenario: Waiting execution is cancelled
- **WHEN** an operator cancels an execution waiting on an approval or context
  expansion
- **THEN** the matching pending request MUST become cancelled with the same
  cancellation operation before the execution cancellation commits

### Requirement: Context Expansion Decisions Are Separate From Tool Approval
Office Graph SHALL distinguish context-expansion authority from model, tool,
credential, mutation, and external-write approval.

#### Scenario: Tool approval is granted
- **WHEN** an actor approves one tool request
- **THEN** that decision MUST NOT grant additional graph scope, context, other
  tools, credentials, or future executions
