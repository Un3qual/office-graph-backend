# idempotency-and-replay Specification

## Purpose
TBD - created by archiving change design-ingestion-and-integrations. Update Purpose after archive.
## Requirements
### Requirement: Idempotent Ingestion
Office Graph SHALL define idempotency basis for manual intake, webhooks, API
polling, replay, model outputs, and tool outputs.

#### Scenario: Ingested event is retried
- **WHEN** an event is retried with the same source identity and idempotency
  basis
- **THEN** Office Graph MUST find the existing sync event or operation and
  avoid duplicating durable domain mutations

#### Scenario: Duplicate is semantically different
- **WHEN** an event has the same source identity but incompatible content,
  timestamp, sequence, digest, or affected resource state
- **THEN** Office Graph MUST reject it, merge it through a domain action, or
  place it into a conflict/review state according to adapter and domain policy

#### Scenario: Orchestrated flow owns derived step keys
- **WHEN** a workflow command derives per-step operation idempotency keys from a
  higher-level flow identity
- **THEN** those step keys MUST be namespaced away from standalone command
  idempotency keys or validate the same flow digest before replaying durable
  step results

### Requirement: Replay And Out-Of-Order Handling
Office Graph SHALL support replay without corrupting product truth.

#### Scenario: Event is replayed
- **WHEN** an archived event is replayed for debugging, recovery, or adapter
  upgrade
- **THEN** replay MUST preserve source identity, replay identity, actor or
  system principal, operation correlation, and duplicate handling outcome

#### Scenario: Event arrives out of order
- **WHEN** an event arrives before a dependency or after a newer state has
  already been applied
- **THEN** Office Graph MUST apply it only if the owning domain can merge it
  safely; otherwise it MUST mark it pending dependency, skipped, retryable
  failure, terminal failure, or conflict
