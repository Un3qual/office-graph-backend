## ADDED Requirements

### Requirement: MVP Agent Invocation Is Run Linked

Office Graph SHALL start the first internal agents through explicit invocations
linked to an existing authorized work run and selected graph context.

#### Scenario: Operator invokes an agent

- **WHEN** an authorized operator selects an active run, graph item, agent
  definition, outcome, and autonomy mode
- **THEN** AgentRuntime MUST create or replay one execution with operation,
  agent principal, delegator, context package, and immutable authority snapshot

#### Scenario: Delegator requests capabilities

- **WHEN** an operator invocation requests the definition's declared
  capabilities
- **THEN** the immutable authority snapshot MUST contain only capabilities also
  granted to the delegating principal and MUST reject any requested capability
  outside that intersection

#### Scenario: Automatic run review starts

- **WHEN** a declared system trigger requests the bound run-review agent for an
  authorized run and selected graph context
- **THEN** AgentRuntime MUST validate the generic system operation, definition
  binding, run, scope, and trigger authority before enqueueing execution

#### Scenario: Automatic trigger lineage does not match the run binding

- **WHEN** a system operation has generic runtime authority but its authority
  basis, causation key, or idempotency scope does not name the exact binding and
  run
- **THEN** AgentRuntime MUST reject the invocation before creating an execution

#### Scenario: Existing invocation is replayed after lifecycle deactivation

- **WHEN** an exact persisted invocation operation is replayed after its binding
  or definition becomes inactive
- **THEN** AgentRuntime MUST return the historical execution without authorizing
  a new invocation

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

#### Scenario: Invocation lacks authority for a governed output

- **WHEN** validated adapter output requires an owning-domain capability absent
  from the immutable authority snapshot
- **THEN** AgentRuntime MUST reject it before calling the owning domain command

#### Scenario: Routed output operation does not match the durable step

- **WHEN** a routed output presents a generically authorized system operation
  whose authority snapshot, execution causation, or idempotency scope does not
  match the exact context package and durable step
- **THEN** the owning-domain boundary MUST reject it before creating the routed
  record, audit entry, or revision

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

#### Scenario: Definition adapter rotates during an active execution

- **WHEN** a definition selects another adapter after invocation
- **THEN** the active execution MUST resolve only the snapshotted adapter
  key/version and MUST fail closed if that exact version is no longer registered

#### Scenario: Adapter lineage is backfilled into existing snapshots

- **WHEN** a schema upgrade adds the model-adapter key and version to an
  existing immutable authority snapshot
- **THEN** the migration MUST recompute the canonical authority hash so valid
  queued or waiting executions remain revalidatable
