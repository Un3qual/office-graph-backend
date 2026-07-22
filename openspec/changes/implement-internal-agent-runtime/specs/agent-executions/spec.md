## ADDED Requirements

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
  when supported, and historical records MUST remain

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
