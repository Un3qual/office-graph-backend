## ADDED Requirements

### Requirement: Integration Health Is Bounded And Safe

Office Graph SHALL expose organization-scoped installation, sync, credential,
retry, and terminal-state summaries without raw payloads, secrets, provider
tokens, or internal exception text.

#### Scenario: Authorized operator reads health

- **WHEN** an authorized operator reads GitHub integration health
- **THEN** Office Graph MUST return installation lifecycle, permission posture,
  last successful sync, bounded retry/terminal counts, and safe remediation codes

#### Scenario: Retryable reconciliation later succeeds

- **WHEN** a retryable reconciliation outcome is updated to successful
- **THEN** health MUST report the successful transition time rather than the
  original failed-attempt insertion time

#### Scenario: Successful outcomes outnumber the health limit

- **WHEN** newer successful outcomes exceed the requested display limit while an
  older classified failure remains
- **THEN** health MUST filter classified failures before applying the bounded
  display limit so the failure and its safe remediation remain visible

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
