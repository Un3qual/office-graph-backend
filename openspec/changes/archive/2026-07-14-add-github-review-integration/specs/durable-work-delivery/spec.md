## ADDED Requirements

### Requirement: Declared System Jobs May Be Organization Scoped

Office Graph SHALL support durable system jobs authenticated by a service or
webhook-source principal when no human session exists.

#### Scenario: Organization-scoped webhook job is recorded

- **WHEN** an authenticated provider delivery applies to an organization but no
  governing workspace or subject version is known
- **THEN** DurableDelivery MUST accept absent workspace or subject/version only
  for the declared system job kind and MUST retain organization, principal,
  authority basis, causation, and idempotency scope

#### Scenario: Human command omits session or workspace

- **WHEN** a human/API operation attempts to use system-job nullability
- **THEN** DurableDelivery MUST reject it and MUST preserve the existing human
  session and workspace requirements

#### Scenario: System job is replayed

- **WHEN** the same organization, source, job kind, and idempotency identity are
  recorded again
- **THEN** DurableDelivery MUST return the existing event/job without duplicate
  work

### Requirement: System Invalidations Respect Governing Scope

Office Graph SHALL publish organization-scoped invalidations without exposing
workspace-specific data to unauthorized subscribers.

#### Scenario: System event has no governing workspace

- **WHEN** an organization-scoped event is dispatched
- **THEN** its invalidation MUST use an organization-owned topic/contract and
  subscribers MUST reauthorize before reading affected workspace resources
