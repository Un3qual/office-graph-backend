# agent-executions Specification

## Purpose
Define child agent invocations, their authority inheritance, and their relationship to parent runtime work.
## Requirements
### Requirement: Agent Executions Are Child Runtime Invocations

Office Graph SHALL represent each internal agent runtime invocation as an agent
execution that is normally linked to a parent work run.

#### Scenario: Agent execution starts inside a work run

- **WHEN** Office Graph invokes an internal agent to investigate, plan, propose,
  verify, summarize, or execute one step of selected work
- **THEN** Office Graph MUST create or be able to create an agent execution
  linked to the parent work run, selected sub-objective, invocation mode,
  initiating principal or trigger, agent principal, context package, autonomy
  envelope, and operation context

#### Scenario: Agent execution is not the whole work run

- **WHEN** a work run invokes multiple agents, retries one agent, hands off to a
  human, imports provider status, or waits for verification
- **THEN** each agent invocation MUST remain a child agent execution and MUST
  NOT overwrite the parent work run's selected work, aggregate status, or
  verification result

### Requirement: Agent Execution Authority Is Explicit

Office Graph SHALL record the effective authority boundary for each agent
execution.

#### Scenario: Agent execution authority is evaluated

- **WHEN** an agent execution starts or requests a tool, credential, context
  expansion, external write, change proposal, or domain action
- **THEN** Office Graph MUST evaluate and record delegator or trigger
  authority, agent principal capability, scope, autonomy envelope, tool or
  integration scope, sensitivity labels, temporary grants, and policy result

#### Scenario: Agent execution lacks authority

- **WHEN** the agent execution lacks authority for requested context, tool use,
  credential access, mutation, external write, or verification action
- **THEN** Office Graph MUST deny the step, request approval, request context
  expansion, downgrade to proposal-only behavior, or block the execution
  according to policy

### Requirement: Agent Execution Events Capture Product-Relevant Steps

Office Graph SHALL preserve product-relevant agent execution events without
turning low-level runtime traces into the product timeline by default.

#### Scenario: Agent execution produces durable outputs

- **WHEN** an agent execution selects context, evaluates authority, calls a
  tool, creates a finding, creates a change proposal, emits an evidence
  candidate, requests approval, fails, retries, or completes
- **THEN** Office Graph MUST preserve an agent-execution event or equivalent
  typed reference sufficient to explain the output, failure, or handoff

#### Scenario: Runtime emits low-level traces

- **WHEN** the runtime produces token-level, prompt-debug, worker-debug, or
  provider-specific traces that are not product-relevant
- **THEN** Office Graph MUST NOT require those traces to become
  agent-execution events, though they may be logged or archived according to
  retention and AI data-control policy

### Requirement: Agent Outputs Route To Owning Domain Contracts

Office Graph SHALL treat agent outputs as untrusted structured outputs until
they are validated and routed to the owning domain.

#### Scenario: Agent proposes a mutation

- **WHEN** an agent execution produces a graph or domain mutation suggestion
- **THEN** Office Graph MUST route it through change-proposal validation,
  authorization, approval, and domain-action application rather than letting
  the agent execution write graph truth directly

#### Scenario: Agent produces verification material

- **WHEN** an agent execution produces a finding, check result, summary,
  artifact, monitoring conclusion, or other verification material
- **THEN** Office Graph MUST classify it as a finding, observation, evidence
  candidate, change-proposal input, or another typed output before it can
  satisfy verification

### Requirement: Agent Executions Follow A Durable State Machine
Office Graph SHALL persist queued, running, waiting-approval, waiting-context,
retry-scheduled, completed, failed, and cancelled execution states with
versioned transitions.

#### Scenario: Durable step completes
- **WHEN** a model, tool, approval, expansion, proposal, or evidence step
  completes
- **THEN** the runtime MUST record the step outcome and execution transition
  before enqueueing the next step

#### Scenario: Process restarts during a step
- **WHEN** a worker terminates after an external/model result but before the next
  step is dispatched
- **THEN** replay MUST use step idempotency and persisted outcome to avoid
  duplicate effects and continue or terminalize deterministically

#### Scenario: Execution is cancelled
- **WHEN** an authorized actor cancels an active or waiting execution
- **THEN** new steps MUST stop, active adapter cancellation MUST be requested
  from the key/version on the active request when supported, matching pending
  gates MUST be cancelled atomically, and historical records MUST remain

#### Scenario: Cancellation operation is replayed

- **WHEN** an exact cancellation operation is replayed for an execution with a
  persisted model request
- **THEN** the runtime MUST return the persisted cancellation result and reissue
  the adapter's idempotent cancellation signal

#### Scenario: Runtime context cannot be loaded

- **WHEN** a queued step cannot resolve its persisted adapter or other durable
  runtime configuration
- **THEN** the execution MUST transition to a durable failed state instead of
  completing its only job while remaining queued

#### Scenario: Transient storage failure occurs before a claim

- **WHEN** context loading or mutable-authority revalidation returns a storage
  availability failure before the step is claimed
- **THEN** the worker MUST retry without consuming an execution attempt or
  recording authority revocation

### Requirement: Execution Retries Are Bounded And Classified
Office Graph SHALL retry only failures classified as retryable and SHALL retain
terminal failure reason codes without raw provider/model exception text.

#### Scenario: Retryable adapter failure occurs
- **WHEN** an adapter returns retryable with bounded backoff data
- **THEN** the step MUST enter retry-scheduled with incremented attempt and one
  unique retry job

#### Scenario: Attempt budget is exhausted
- **WHEN** a retryable failure reaches its declared attempt or time budget
- **THEN** the execution MUST become failed with a safe terminal classification

#### Scenario: Governed output routing rejects a completed adapter result

- **WHEN** an adapter succeeds but output validation or the owning domain rejects
  the routed result
- **THEN** the model request and execution MUST transition through the durable
  retry or terminal-failure path and MUST NOT remain running with an expired
  lease

#### Scenario: Output validation encounters transient storage failure

- **WHEN** system-principal authorization storage is temporarily unavailable
  while a completed adapter result is being routed
- **THEN** output validation MUST preserve the storage-availability
  classification so the worker uses its bounded retry path instead of recording
  a terminal authorization or routing failure
