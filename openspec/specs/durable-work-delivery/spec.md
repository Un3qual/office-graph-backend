# durable-work-delivery Specification

## Purpose
TBD - created by archiving change add-durable-work-delivery. Update Purpose after archive.
## Requirements
### Requirement: Durable Work Uses Postgres-Backed Jobs

Office Graph SHALL use Oban as the durable owner for retryable integration,
agent, verification, projection, and maintenance work.

#### Scenario: Command requests durable work

- **WHEN** a committed domain command requires asynchronous follow-up
- **THEN** it MUST insert an Oban job with stable queue, worker, operation,
  scope, and idempotency identity in the same database transaction as the
  durable request for that work

#### Scenario: Command transaction rolls back

- **WHEN** the owning product transaction fails after requesting work
- **THEN** neither the domain event nor its Oban job may remain committed

### Requirement: Domain Events Are Typed And Correlated

Office Graph SHALL persist typed domain-event facts without copying product
state into a generic event payload.

#### Scenario: Domain event is recorded

- **WHEN** a meaningful domain command records an event
- **THEN** the event MUST preserve event kind, subject kind and identity,
  optional subject version, organization, optional workspace, operation,
  optional causation, occurrence time, and delivery state

#### Scenario: Event is replayed

- **WHEN** the same operation and event identity is recorded again
- **THEN** Office Graph MUST return the existing event and MUST NOT enqueue or
  publish a duplicate durable effect

### Requirement: Worker Failures Have Stable Classification

Office Graph SHALL distinguish retryable worker failures from terminal failures
without exposing internal exceptions as product data.

#### Scenario: Worker failure is retryable

- **WHEN** a worker returns a classified transient failure before exhausting
  its attempt budget
- **THEN** Oban MUST retain the job for bounded retry and telemetry MUST record
  the failed attempt

#### Scenario: Dispatch terminates before returning a classified result

- **WHEN** event dispatch raises, exits, or throws before returning a result
- **THEN** Office Graph MUST convert the termination into a stable retryable
  failure so exhausted delivery attempts still record a terminal event state

#### Scenario: Worker failure is terminal

- **WHEN** a worker returns a classified terminal failure or exhausts its
  bounded attempt budget
- **THEN** the job MUST stop retrying and a scoped operator read MUST expose its
  stable state, safe reason, attempts, queue, worker, and timestamps throughout
  the configured operator-history retention window

#### Scenario: Terminal event persistence is temporarily unavailable

- **WHEN** a delivery attempt reaches a terminal result but persisting the
  event's failed state does not succeed
- **THEN** the worker MUST retain a safe terminalization phase and retry that
  state transition without broadcasting the event again or cancelling the job
  first

#### Scenario: Terminal job has no matching event state

- **WHEN** a cancelled delivery job refers to a missing, mismatched-scope, or
  malformed event identity
- **THEN** the scoped operator read MUST remain available and MUST expose the
  worker's persisted safe terminal reason without interpreting raw job errors

#### Scenario: Terminal history authorization changes

- **WHEN** a principal's durable-delivery read grant is revoked while its
  session remains active
- **THEN** subsequent terminal-history reads MUST recheck current grants and
  fail closed

#### Scenario: Existing owners upgrade to durable delivery

- **WHEN** durable delivery is deployed to an organization whose owner roles
  predate the durable-delivery read capability
- **THEN** the upgrade MUST grant that capability to those existing owner roles
  without requiring the local bootstrap workflow to run again

#### Scenario: A delivery job carries the wrong scope

- **WHEN** a delivery job's organization or workspace does not match its event
- **THEN** the worker MUST fail closed without broadcasting or changing the
  event

#### Scenario: Terminal failure races with successful dispatch

- **WHEN** terminal failure handling overlaps a successful event dispatch
- **THEN** the event transition MUST be serialized and a dispatched event MUST
  NOT be overwritten as failed

#### Scenario: Terminal history is pruned

- **WHEN** terminal jobs age beyond the configured operator-history retention
  window
- **THEN** Office Graph MAY prune them to keep infrastructure storage bounded

### Requirement: Durable Work Emits Operational Telemetry

Office Graph SHALL emit bounded telemetry for durable job execution without
including raw arguments or tenant-sensitive data.

#### Scenario: Job attempt finishes

- **WHEN** an Oban job succeeds, fails, retries, is cancelled, or is discarded
- **THEN** telemetry MUST expose worker, queue, state, attempt, and duration
  metadata sufficient for operational metrics
