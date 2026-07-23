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

#### Scenario: Duplicate or stale worker cannot overwrite active execution state

- **WHEN** runtime configuration failure is discovered by a duplicate worker
  while the matching step has a lease or by a prior-step worker after the
  execution has advanced
- **THEN** the worker MUST preserve the active request, lease, current step, and
  execution state and MUST snooze or complete the obsolete job without a
  terminal transition

#### Scenario: Persisted step becomes terminally invalid before recovery

- **WHEN** a matching retry-scheduled request or lease-expired running request
  discovers a terminal authority or runtime-configuration failure
- **THEN** the worker MUST atomically fail that typed request and execution,
  clear the expired lease, and preserve their shared failure classification

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
