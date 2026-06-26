# agent-runtime Specification

## Purpose
TBD - created by archiving change design-agent-runtime. Update Purpose after archive.
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
