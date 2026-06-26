# integration-principal-operation-linkage Specification

## Purpose
TBD - created by archiving change design-integration-source-principals. Update Purpose after archive.
## Requirements
### Requirement: Source Principal Operation Linkage
Office Graph SHALL link source principal context to operation correlation for
meaningful integration commands, observed events, credential uses, and replay
attempts.

#### Scenario: Integration operation is recorded
- **WHEN** a webhook source, integration installation, service account, system
  job, human, agent, external executor, or replay job performs or observes a
  meaningful integration action
- **THEN** Office Graph MUST be able to record operation correlation with
  organization, applicable scopes, source principal, installation principal,
  credential principal or credential metadata when applicable, actor or
  delegator when applicable, command key, authority basis, idempotency basis,
  request or trace identifiers, source surface, and timestamps

#### Scenario: One integration event writes several record families
- **WHEN** one integration event creates external sync events, authorization
  decisions, audit records, domain events, change proposals, evidence,
  revisions, or provider-neutral resource updates
- **THEN** those records MUST be linkable through the same operation
  correlation identifier without copying each other's payloads

### Requirement: Idempotency Includes Source Principal Context
Office Graph SHALL derive integration idempotency and replay identity from
source identity plus relevant source-principal context.

#### Scenario: Provider delivery is retried
- **WHEN** a provider retries a webhook delivery or Office Graph retries a
  provider polling/import operation
- **THEN** idempotency MUST consider source identity, installation principal,
  organization, provider event or cursor identity, delivery or sequence
  identity, credential basis when relevant, payload digest when available, and
  replay identity when the event is replayed

#### Scenario: Same provider event arrives through different authority
- **WHEN** the same provider event identifier arrives through a different
  organization, installation principal, credential principal, allowed scope, or
  replay job
- **THEN** Office Graph MUST treat the authority context as part of the
  duplicate/conflict decision instead of blindly merging the events

### Requirement: Audit And Authorization Linkage For Integration Authority
Office Graph SHALL link policy-sensitive integration authority decisions to
authorization decision records and durable audit records when required.

#### Scenario: Credential use is policy-sensitive
- **WHEN** an integration, agent, service account, system job, external
  executor, or human action uses or attempts to use credential metadata for a
  provider read, provider write, webhook verification, source replay, or
  external callback
- **THEN** Office Graph MUST be able to record the authorization decision,
  policy bundle version, operation correlation, credential metadata reference,
  source principal context, result, and audit event when policy requires
  durable audit

#### Scenario: Integration action is denied or escalated
- **WHEN** source verification, credential use, provider write, external
  callback, scope expansion, quarantine release, or replay is denied,
  redacted, approval-gated, or escalated
- **THEN** Office Graph MUST preserve the decision, authority basis, related
  operation, relevant principal roles, and policy-approved audit evidence

### Requirement: Replay Preserves Source Authority
Office Graph SHALL preserve original and replay-time authority context when
archived integration events are replayed.

#### Scenario: Archived event is replayed
- **WHEN** an archived webhook, provider API payload, external executor
  callback, raw delivery, or normalized event is replayed for recovery,
  debugging, support, security review, or adapter upgrade
- **THEN** replay MUST preserve original source principal context, replaying
  principal, replay authority basis, replay identity, operation correlation,
  external sync event linkage, duplicate outcome, and applied/skipped/failed
  result
