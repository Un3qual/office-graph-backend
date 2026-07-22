## ADDED Requirements

### Requirement: MVP Agent Invocation Is Run Linked

Office Graph SHALL start the first internal agents through explicit invocations
linked to an existing authorized work run and selected graph context.

#### Scenario: Operator invokes an agent

- **WHEN** an authorized operator selects an active run, graph item, agent
  definition, outcome, and autonomy mode
- **THEN** AgentRuntime MUST create or replay one execution with operation,
  agent principal, delegator, context package, and immutable authority snapshot

#### Scenario: Automatic OpenSpec review starts

- **WHEN** a declared system trigger requests the bound OpenSpec review agent
- **THEN** AgentRuntime MUST validate the generic system operation, definition
  binding, run, scope, and trigger authority before enqueueing execution

### Requirement: Agent Runtime Is Proposal First

Office Graph SHALL route initial agent contributions through conversation,
finding, proposed-change, observation, or evidence-candidate contracts without
direct business mutation or external write.

#### Scenario: Agent suggests durable graph work

- **WHEN** validated model or tool output requests a graph/domain mutation
- **THEN** AgentRuntime MUST create proposal input through the owning domain and
  MUST NOT write graph truth directly

#### Scenario: Definition disallows an output classification

- **WHEN** validated adapter output is outside the active definition's output
  allowlist
- **THEN** AgentRuntime MUST reject it before calling an owning domain command

#### Scenario: Agent requests unsupported external write

- **WHEN** an initial agent requests a provider mutation or other external write
- **THEN** the runtime MUST deny it before credential or adapter execution

### Requirement: Mutable Authority Is Rechecked Before Each Step

Office Graph SHALL preserve the start authority snapshot and revalidate mutable
principal, credential, grant, tool, and approval state before executing each
durable step.

#### Scenario: Credential or agent principal is revoked mid-run

- **WHEN** a queued or retrying step reaches execution after revocation
- **THEN** the runtime MUST fail closed or request new authority without erasing
  prior execution history

#### Scenario: Definition credential rotates during an active execution

- **WHEN** a definition selects a new active credential after an execution has
  captured its immutable authority snapshot
- **THEN** the active execution MUST retain the snapshotted credential reference
  for request provenance while later invocations capture the rotated credential
