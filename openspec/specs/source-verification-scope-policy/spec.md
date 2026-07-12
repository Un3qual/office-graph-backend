# source-verification-scope-policy Specification

## Purpose
Define authentication and scope checks that external sources must pass before normalization.
## Requirements
### Requirement: Source Verification Before Normalization
Office Graph SHALL verify inbound source identity and allowed event scope
before a provider adapter may normalize an event into a provider-neutral
envelope.

#### Scenario: Inbound webhook is received
- **WHEN** Office Graph receives a webhook delivery, callback, provider push
  event, external executor callback, or signed provider notification
- **THEN** it MUST authenticate the source proof, evaluate source principal
  lifecycle, validate credential metadata state, check provider and tenant
  identity, and confirm the event type is allowed for the registered source

#### Scenario: Source proof fails
- **WHEN** source proof is missing, invalid, expired, outside the replay
  window, signed by a revoked credential, or mismatched to the claimed
  provider or tenant
- **THEN** Office Graph MUST reject or quarantine the event before adapter
  normalization and MUST preserve only policy-approved traceability metadata

### Requirement: Allowed Provider Event And Resource Scopes
Office Graph SHALL evaluate allowed provider, event, resource, and Office
Graph scopes for integration events and provider API use.

#### Scenario: Event is outside allowed scope
- **WHEN** a verified source sends an event for a provider object, tenant,
  account, repository, channel, project, external source, workspace,
  initiative, or sensitivity class outside the installation or credential's
  allowed scopes
- **THEN** Office Graph MUST skip, reject, quarantine, or escalate the event
  according to policy without mutating product truth

#### Scenario: Provider write is requested
- **WHEN** a human, agent, service account, system job, or integration requests
  an external provider write
- **THEN** Office Graph MUST evaluate external-write capability, integration
  installation scope, credential metadata scope, resource sensitivity, related
  work packet or run policy when applicable, and approval requirements before
  secret access or provider use

### Requirement: Credential Metadata Drives Source Authority
Office Graph SHALL use secret-free credential metadata and normalized allowed
scope/capability facts as the product-data basis for source verification and
credentialed provider access.

#### Scenario: Credential metadata is selected
- **WHEN** an integration handler or adapter needs a webhook secret, signing
  key, provider API token, app credential, external executor credential, or
  service account token
- **THEN** it MUST identify credential metadata, lifecycle state, owner
  principal, allowed scopes, allowed capabilities, sensitivity, rotation or
  revocation state, and SecretStore reference before secret value access is
  authorized

#### Scenario: Credential has no allowed capability
- **WHEN** credential metadata is valid but does not allow the requested event,
  provider API operation, external write, provider read, webhook verification,
  or executor callback
- **THEN** Office Graph MUST deny the use and record a policy-approved
  operation, authorization decision, audit, or sync failure linkage when the
  attempt is policy-sensitive

### Requirement: Source Failure And Quarantine States
Office Graph SHALL preserve shared failure and quarantine states for source
verification and scope enforcement outcomes.

#### Scenario: Event cannot be trusted
- **WHEN** an event fails because the source is unknown, unverified, disabled,
  revoked, expired, replayed outside policy, tenant-mismatched,
  provider-mismatched, event-denied, scope-mismatched, sensitivity-denied,
  conflicting, retryable, or terminally failed
- **THEN** Office Graph MUST assign a shared failure or quarantine outcome that
  maps to ingestion sync state and supportable operation records

#### Scenario: Quarantined event is reviewed
- **WHEN** a quarantined event is reviewed, released, replayed, redacted,
  discarded, or escalated
- **THEN** Office Graph MUST preserve the original source principal context,
  raw archive or delivery reference when retained, reviewer or automation
  principal, authority basis, operation correlation, and final outcome
