# integration-health Specification

## Purpose

Define safe, tenant-scoped, query-bounded operational health projections for
external integrations.

## Requirements

### Requirement: Integration Health Is Bounded And Safe

Office Graph SHALL expose organization-scoped installation, sync, credential,
retry, and terminal-state summaries without raw payloads, secrets, provider
tokens, or internal exception text.

#### Scenario: Authorized operator reads health

- **WHEN** an authorized operator reads GitHub integration health
- **THEN** Office Graph MUST return installation lifecycle, permission posture,
  last successful sync, complete retry/terminal counts, a bounded recent-failure
  sample, and safe remediation codes

#### Scenario: Workspace operator requests organization-scoped health

- **WHEN** an operator whose health-read authority is assigned only to the
  current workspace requests an organization-scoped installation
- **THEN** Office Graph MUST return a non-enumerating forbidden response without
  exposing organization-level permission, credential, or failure posture

#### Scenario: Required GitHub permissions are incomplete

- **WHEN** an installation permission snapshot lacks write access to checks or
  pull requests
- **THEN** health MUST report an insufficient permission posture and safe
  installation-reauthorization remediation

#### Scenario: Provider rejects an action after permissions change

- **WHEN** a recent GitHub outbound action has an authorization-class
  `permission_denied` failure
- **THEN** health MUST expose safe installation-reauthorization remediation even
  when the stored permission snapshot still appears configured

#### Scenario: Retryable reconciliation later succeeds

- **WHEN** a retryable reconciliation outcome is updated to successful
- **THEN** health MUST report the successful transition time rather than the
  original failed-attempt insertion time

#### Scenario: Successful outcomes outnumber the health limit

- **WHEN** newer successful outcomes exceed the requested display limit while an
  older classified failure remains
- **THEN** health MUST filter classified failures before applying the bounded
  display limit so the failure and its safe remediation remain visible

#### Scenario: Classified failures outnumber the health limit

- **WHEN** retryable or terminal outcomes and actions exceed the requested
  recent-failure display limit
- **THEN** health MUST report complete retryable and terminal headline counts
  while keeping the recent-failure collection bounded to the requested limit

#### Scenario: Other tenant health is requested

- **WHEN** an actor requests an installation outside authorized organization or
  workspace scope
- **THEN** Office Graph MUST return a non-enumerating forbidden or not-found
  response and MUST NOT reveal installation existence

#### Scenario: Health dependency storage is temporarily unavailable

- **WHEN** health cannot read or aggregate installation permissions,
  credentials, synchronization outcomes, or outbound actions because storage is
  temporarily unavailable
- **THEN** Office Graph MUST return a safe storage-unavailable classification
  without exposing or raising an internal storage exception

### Requirement: Health Reads Are Query-Bounded

Office Graph SHALL assemble integration health without query count growing per
repository, delivery, or terminal job.

#### Scenario: Installation owns many records

- **WHEN** health is read for installations with increasing repositories,
  deliveries, and jobs
- **THEN** query count MUST remain within the documented constant or batched
  bound and collection fields MUST be paginated or summarized
