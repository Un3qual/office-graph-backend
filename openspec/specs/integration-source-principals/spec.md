# integration-source-principals Specification

## Purpose
Define authenticated source-principal context for integrations before provider data enters the graph.
## Requirements
### Requirement: Integration Source Principal Context
Office Graph SHALL model integration source principal context as distinct
principal roles instead of collapsing every integration event into one actor.

#### Scenario: Webhook event is attributed
- **WHEN** a webhook event is received from a registered provider source
- **THEN** Office Graph MUST identify the webhook source principal,
  integration installation principal, credential principal when verification
  uses credential metadata, provider actor principal or actor hint when known,
  organization, applicable scopes, and authority basis before the event can be
  applied to product truth

#### Scenario: Provider API access is attributed
- **WHEN** Office Graph polls a provider API, reads provider state, or calls a
  provider API for an integration
- **THEN** the operation MUST identify the integration installation principal,
  service account or credential principal, initiating human, agent, system job,
  or run when applicable, allowed scopes, requested capability, and authority
  basis

#### Scenario: Source role is unknown or ambiguous
- **WHEN** an inbound event or provider response cannot be mapped to a trusted
  source principal context
- **THEN** Office Graph MUST reject, quarantine, or hold the event for review
  without creating or mutating Office Graph domain truth

### Requirement: Integration Installation Principal Mapping
Office Graph SHALL represent integration installations as principals whose
authority is scoped by organization, provider, installation, credential
metadata, capabilities, and lifecycle state.

#### Scenario: Installation receives an event
- **WHEN** a provider event names or implies an installation, app instance,
  workspace, organization, repository, project, channel, tenant, or account
- **THEN** Office Graph MUST map that provider installation context to an
  internal integration installation principal and authorization scope before
  adapter normalization proceeds

#### Scenario: Installation is disabled or revoked
- **WHEN** an event or provider API request targets a disabled, revoked,
  expired, suspended, or deprovisioned installation principal
- **THEN** Office Graph MUST fail closed, preserve operation or sync
  traceability, and prevent credential use or domain mutation unless a
  policy-approved reauthorization path succeeds

### Requirement: Actor And Delegation Basis Preservation
Office Graph SHALL preserve provider actor, Office Graph actor, delegated
authority, and trigger basis separately when they differ.

#### Scenario: Provider user caused a webhook
- **WHEN** a provider webhook identifies an external user, bot, service, or
  app actor that caused the provider-side event
- **THEN** Office Graph MUST preserve that actor as a provider actor hint,
  external identity link candidate, or mapped principal without treating the
  provider actor as direct Office Graph authority unless reconciliation and
  authorization policy allow it

#### Scenario: Agent or system job uses an integration
- **WHEN** an agent run, approved work packet, system job, replay job, or
  support action uses an integration credential or receives provider state
- **THEN** Office Graph MUST preserve the executing principal, delegator or
  trigger authority basis, related run or work packet when applicable, and
  integration principal context for authorization, replay, and audit
