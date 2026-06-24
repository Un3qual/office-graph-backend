# provider-adapter-principal-consumption Specification

## Purpose
TBD - created by archiving change design-integration-source-principals. Update Purpose after archive.
## Requirements
### Requirement: Provider Adapters Consume Verified Source Context
Office Graph provider adapters SHALL consume verified source-principal context
as input and emit provider-neutral envelopes that preserve authority and
credential basis.

#### Scenario: Adapter normalizes verified input
- **WHEN** a provider adapter normalizes a webhook, provider API payload,
  polling result, external executor callback, replayed event, model output, or
  tool output
- **THEN** the adapter output MUST include source identity, source principal
  context, integration installation principal when applicable, credential
  metadata reference when applicable, normalized event kind, raw archive or
  delivery reference, idempotency basis, operation context input, affected
  external references, and intended domain action

#### Scenario: Adapter receives unverified input
- **WHEN** provider input has not passed source verification or scope
  enforcement
- **THEN** the adapter MUST NOT emit an application-ready provider-neutral
  envelope and MUST return a rejected, failed, or quarantined outcome for the
  ingestion path to record

### Requirement: Adapter Principal Hints Are Not Authorization Decisions
Office Graph provider adapters SHALL emit principal, actor, scope, and
credential hints without deciding final authorization or product truth.

#### Scenario: Adapter identifies a provider actor
- **WHEN** an adapter recognizes a provider user, bot, app, service account,
  executor, organization, team, repository, channel, project, account, or
  other provider authority concept
- **THEN** it MUST emit provider-neutral actor, external identity, external
  reference, scope, or conflict hints without treating external provider names
  as direct Office Graph permissions

#### Scenario: Adapter proposes a domain action
- **WHEN** an adapter output indicates that a signal, evidence item,
  provider-neutral resource, review finding, change proposal, sync event, or
  external reference should be created or updated
- **THEN** Office Graph domain actions and authorization policy MUST decide
  whether to apply, reject, merge, conflict, quarantine, or propose the change

### Requirement: Provider-Specific Extensions Map Back To Shared Contracts
Office Graph provider adapters SHALL map provider-specific source, credential,
event, and replay details back to shared source-principal and sync contracts.

#### Scenario: Provider has custom delivery metadata
- **WHEN** a provider exposes installation ids, app ids, workspace ids,
  organization ids, repository ids, channel ids, cursor positions, delivery
  ids, sequence numbers, signatures, event names, retry headers, or webhook
  replay markers
- **THEN** the adapter MUST map the relevant fields into shared source
  identity, scope, credential metadata, idempotency, replay, and sync-state
  fields before adding provider-specific extension details

#### Scenario: Provider-specific state is stored
- **WHEN** future implementation stores provider-local adapter state,
  extension rows, or adapter-specific delivery metadata
- **THEN** that state MUST remain traceable to the shared source principal,
  operation correlation, external sync state, credential metadata, and raw
  archive or delivery references required by this change
