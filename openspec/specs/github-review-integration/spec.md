# github-review-integration Specification

## Purpose
Define authenticated GitHub App intake, provider-neutral reconciliation,
narrow outbound review actions, and classified failure handling.

## Requirements
### Requirement: GitHub Installations Are Explicitly Bound
Office Graph SHALL bind a GitHub App installation to one organization, optional
governing workspace, service principal, permission snapshot, and credential
references through a narrow authorized command.

#### Scenario: Authorized owner binds installation
- **WHEN** an authorized local owner submits a valid installation identity,
  scope, service principal, permissions, and secret references
- **THEN** Office Graph MUST create or idempotently return the installation
  binding without returning secret values

#### Scenario: Unauthenticated setup is attempted
- **WHEN** a request without an authorized human session attempts to bind an
  installation
- **THEN** Office Graph MUST reject it without revealing another tenant's
  installation state

### Requirement: GitHub Webhooks Are Verified Before Product Intake
Office Graph SHALL verify webhook signature and installation binding before
archiving a payload or creating product work.

#### Scenario: Valid supported delivery arrives
- **WHEN** a supported event has a valid signature and active installation
  binding
- **THEN** Office Graph MUST create a system operation, archive the payload,
  enqueue one durable delivery, and return promptly

#### Scenario: Signature or installation is invalid
- **WHEN** signature verification fails or the installation is unknown, revoked,
  or outside scope
- **THEN** Office Graph MUST reject the delivery before product payload archival
  or job creation

#### Scenario: Delivery is replayed
- **WHEN** GitHub repeats a delivery ID with the same authenticated installation
- **THEN** Office Graph MUST return the prior receipt outcome without duplicate
  resource, signal, event, or job effects

### Requirement: GitHub State Is Reconciled Into Provider-Neutral Resources
Office Graph SHALL reconcile supported repository, pull request, review,
review-comment, and check activity into provider-neutral resources and GitHub
extension records.

#### Scenario: Partial webhook is processed
- **WHEN** a webhook does not contain authoritative current provider state
- **THEN** the durable handler MUST schedule or perform an installation-scoped
  adapter read before updating provider-neutral truth

#### Scenario: Older provider version arrives
- **WHEN** a delivery or reconciliation result is older than the stored provider
  version
- **THEN** Office Graph MUST skip or reconcile it and MUST NOT overwrite newer
  state

#### Scenario: Review signal becomes product work
- **WHEN** a reconciled review comment or failing check matches the proving
  workflow
- **THEN** Office Graph MUST create the authorized signal, external references,
  and canonical typed relationships through owning domain commands

### Requirement: GitHub Outbound Actions Are Narrow And Authorized
Office Graph SHALL expose only review-reply and status/check-update commands for
the first GitHub integration.

#### Scenario: Authorized reply is requested
- **WHEN** an actor with required capability, installation permission,
  credential scope, operation, and idempotency key requests a review reply
- **THEN** Office Graph MUST enqueue one provider action and record its provider
  response identity and classified outcome

#### Scenario: Repository write is requested
- **WHEN** a caller requests a commit, branch write, merge, or other unsupported
  repository mutation
- **THEN** the integration MUST reject it before credential resolution or
  provider access

### Requirement: GitHub Failures Are Classified
Office Graph SHALL classify provider failures as retryable, terminal,
authorization, configuration, rate-limit, or stale-version outcomes.

#### Scenario: GitHub rate limit is returned
- **WHEN** an adapter call returns a valid rate-limit reset
- **THEN** the job MUST retry no earlier than the bounded reset policy and health
  MUST expose a safe rate-limit state

#### Scenario: Installation is revoked
- **WHEN** GitHub reports a revoked installation or invalid credential
- **THEN** new provider work MUST fail closed, active retries MUST become
  configuration or terminal state, and historical provenance MUST remain
