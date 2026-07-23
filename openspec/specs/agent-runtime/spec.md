# agent-runtime Specification

## Purpose
Define governed runtime entry points for agents that inspect graph context and perform authorized work.
## Requirements
### Requirement: Agent Runtime Entry Points
Office Graph SHALL start internal agent activity only through explicit runtime
entry points that identify the agent mode, origin, selected graph context, and
authority basis.

#### Scenario: Embedded agent starts from graph item
- **WHEN** a user opens an embedded agent conversation on an addressable graph
  item
- **THEN** the runtime MUST record the selected graph item, organization,
  workspace or initiative scope, user principal, agent principal when assigned,
  conversation purpose, and authority basis before the agent receives context

#### Scenario: Automatic agent starts from trigger
- **WHEN** an automatic agent starts from a signal, graph event, integration
  event, schedule, policy trigger, or completion event
- **THEN** the runtime MUST record the trigger source, organization, starting
  scopes, agent principal, trigger policy, configured autonomy envelope, and
  required approvals before executing model or tool steps

#### Scenario: Delegated agent starts from user request
- **WHEN** a user delegates work to an internal agent
- **THEN** the runtime MUST record the delegating principal, requested outcome,
  allowed scopes, requested capabilities, autonomy envelope, and whether the
  agent is read-only, proposal-only, write-capable, or external-write-capable

### Requirement: Authorized Context Packages
Office Graph SHALL provide agents with explicit context packages assembled from
authorized graph projections and related typed records.

#### Scenario: Agent context package is assembled
- **WHEN** the runtime prepares context for an embedded, delegated, or automatic
  agent
- **THEN** the context package MUST include the selected graph item or trigger,
  authorized neighboring graph items, relevant typed records, external
  references, rich text references, raw archive references when policy permits,
  prior decisions, checks, evidence, recent runs when available, and projection
  rationale sufficient to explain why the context is present

#### Scenario: Context is restricted
- **WHEN** relevant context is outside the agent's permitted scope,
  classification, data-control policy, credential boundary, or autonomy
  envelope
- **THEN** the runtime MUST omit, redact, summarize, expose a restricted
  placeholder, or request context expansion according to policy rather than
  silently include the restricted context

#### Scenario: Agent cites context boundary
- **WHEN** an agent answer, finding, change proposal, or tool request depends on
  omitted, redacted, summarized, or placeholder context
- **THEN** the runtime MUST preserve enough context-boundary rationale for the
  agent, reviewer, or auditor to understand the limitation when policy permits
  disclosure

### Requirement: Context Expansion Requests
Office Graph SHALL route agent requests for broader context through explicit
context expansion decisions instead of allowing agents to self-expand access.

#### Scenario: Agent needs additional scope
- **WHEN** an agent determines that useful work requires additional workspaces,
  initiatives, repositories, departments, integrations, external artifacts, or
  sensitivity labels
- **THEN** the runtime MUST create a context expansion request that identifies
  target scopes, reason, requested capabilities, sensitivity labels, access
  mode, tool or integration needs, and expected duration

#### Scenario: Expansion decision is returned
- **WHEN** governance, policy, or human approval resolves a context expansion
  request
- **THEN** the runtime MUST continue with the approved context, redacted
  context, summary context, temporary scoped grant, denial, or escalation result
  and MUST preserve the decision reference for later traceability

### Requirement: Model And Tool Separation
Office Graph SHALL separate model output from runtime supervision, tool
execution, durable writes, and external actions.

#### Scenario: Model proposes structured output
- **WHEN** a model produces an answer, finding, task suggestion, edge
  suggestion, evidence summary, or mutation request
- **THEN** the runtime MUST treat the output as untrusted structured output
  that requires validation, authorization, and domain acceptance before it
  becomes durable graph truth

#### Scenario: Agent requests tool execution
- **WHEN** an agent requests a tool call, credential use, external read,
  external write, command execution, provider mutation, or production-affecting
  action
- **THEN** the runtime MUST verify the autonomy envelope, tool permission,
  credential scope, operation context, approval requirements, and data-control
  policy before executing the tool or refusing the request

#### Scenario: Tool output returns to the runtime
- **WHEN** a tool produces output for an agent step
- **THEN** the runtime MUST classify the output as raw payload, observation,
  evidence candidate, change proposal input, or error before any downstream
  domain action consumes it

### Requirement: Durable Mutation Boundaries
Office Graph SHALL route agent-driven durable changes through proposed graph
changes or accepted domain actions rather than hidden runtime side effects.

#### Scenario: Agent suggests graph mutation
- **WHEN** an agent suggests creating, updating, linking, unlinking, closing,
  approving, rejecting, attaching evidence to, or otherwise changing graph or
  domain state
- **THEN** the runtime MUST create a change proposal or invoke an
  accepted domain action with the same validation, authorization, revision,
  audit, and operation-correlation contracts used by human and integration
  entry points

#### Scenario: Agent is not authorized to mutate
- **WHEN** the requested mutation is outside the agent's authority, autonomy
  envelope, target scope, approval state, or tool permission
- **THEN** the runtime MUST reject the mutation, request approval or expansion,
  or return a proposal-only result without changing durable graph truth

### Requirement: Agent Provenance And Operation Context
Office Graph SHALL preserve provenance and operation context for internal
agent activity that affects graph understanding, durable state, external
systems, or verification.

#### Scenario: Agent produces a durable contribution
- **WHEN** an agent message, answer, finding, change proposal, evidence
  candidate, tool action, external action, or accepted domain action is recorded
- **THEN** the runtime MUST retain agent principal, delegator or trigger
  authority when present, operation context, selected graph item or trigger,
  context package reference, model or tool family when policy permits, timestamp,
  and visibility context sufficient for audit and revision designs

#### Scenario: Runtime step fails
- **WHEN** an agent step fails because of model error, tool error, validation
  failure, authorization denial, approval timeout, context expansion denial, or
  external provider failure
- **THEN** the runtime MUST preserve a failure record or event with the failed
  step type, reason, retry eligibility, and correlation to the run or
  conversation without treating the work as verified completion

### Requirement: Runtime Handoff Contracts
Office Graph SHALL expose explicit handoff contracts from agent runtime
activity to work packets, runs, verification, API/realtime projections, and
review surfaces.

#### Scenario: Agent creates work for later execution
- **WHEN** an agent output becomes a task, readiness issue, work packet
  candidate, approval request, verification check, evidence item, review
  finding, or follow-up run request
- **THEN** the runtime MUST hand it off through the owning domain contract and
  preserve links back to the triggering graph item, context package, agent
  contribution, and operation context

#### Scenario: Runtime state is projected
- **WHEN** an API, realtime subscription, UI projection, or audit/review surface
  displays agent runtime state
- **THEN** the runtime MUST expose enough status, authority, context-boundary,
  approval, failure, and provenance information for the surface to explain what
  the agent can see, what it can do, what it has done, and what still requires
  human or policy approval

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
