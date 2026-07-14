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
  last successful sync, bounded retry/terminal counts, and safe remediation codes

#### Scenario: Other tenant health is requested

- **WHEN** an actor requests an installation outside authorized organization or
  workspace scope
- **THEN** Office Graph MUST return a non-enumerating forbidden or not-found
  response and MUST NOT reveal installation existence

### Requirement: Health Reads Are Query-Bounded

Office Graph SHALL assemble integration health without query count growing per
repository, delivery, or terminal job.

#### Scenario: Installation owns many records

- **WHEN** health is read for installations with increasing repositories,
  deliveries, and jobs
- **THEN** query count MUST remain within the documented constant or batched
  bound and collection fields MUST be paginated or summarized
