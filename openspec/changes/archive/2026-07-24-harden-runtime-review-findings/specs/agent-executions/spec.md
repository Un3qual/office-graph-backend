## MODIFIED Requirements

### Requirement: Agent Outputs Route To Owning Domain Contracts

Office Graph SHALL treat agent outputs as untrusted structured outputs until
they are validated and routed to the owning domain. Routing and execution
completion SHALL commit in one transaction, and each owning domain SHALL
deduplicate effects by stable execution and step identity.

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

#### Scenario: Routed output is replayed

- **WHEN** a completed execution step is replayed with the same operation,
  context, and validated output
- **THEN** the owning domain MUST return the existing step-owned result without
  duplicate effects, and changed replay input MUST conflict

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
- **WHEN** a worker terminates while its durable Oban job owns a running or
  retry-scheduled step
- **THEN** orphan recovery MUST make that same job eligible again, and replay
  MUST use step idempotency and persisted outcome to avoid duplicate effects
  and continue or terminalize deterministically

#### Scenario: Execution is cancelled
- **WHEN** an authorized actor cancels an active or waiting execution
- **THEN** new steps MUST stop, a worker holding a claim MUST revalidate its
  request, execution state, and lease immediately before adapter dispatch,
  active adapter cancellation MUST be requested from the key/version on the
  active request when supported, matching pending gates MUST be cancelled
  atomically, and historical records MUST remain

#### Scenario: Cancellation operation is replayed

- **WHEN** an exact cancellation operation is replayed for an execution with a
  persisted model request
- **THEN** the runtime MUST return the persisted cancellation result and reissue
  the adapter's idempotent cancellation signal

#### Scenario: Runtime context cannot be loaded

- **WHEN** a queued step permanently cannot resolve missing or invalid persisted
  adapter or other durable runtime configuration
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
- **THEN** the step MUST enter retry-scheduled with incremented attempt and the
  current durable Oban job MUST be snoozed rather than creating a second retry
  job

#### Scenario: Attempt budget is exhausted
- **WHEN** a retryable failure reaches its declared attempt or time budget
- **THEN** the execution MUST become failed with a safe terminal classification

#### Scenario: Governed output routing rejects a completed adapter result

- **WHEN** an adapter succeeds but permanent output validation or the owning
  domain's business rules reject the routed result
- **THEN** the model request and execution MUST transition to terminal failure
  and MUST NOT remain running with an expired lease

#### Scenario: Owning-domain output routing encounters transient storage failure

- **WHEN** Ash or database storage is temporarily unavailable anywhere while a
  completed adapter result is being routed through its owning domain
- **THEN** output routing MUST preserve the retryable infrastructure-failure
  classification so the worker uses its bounded retry path and MUST NOT record
  a terminal business failure
