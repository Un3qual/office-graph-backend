# credential-security Specification

## Purpose
Define scoped credential, secret storage, webhook principal, external write, rotation, and revocation requirements.

## Requirements

### Requirement: Credentials As Scoped Governance Resources
Office Graph SHALL model integration credentials, tool tokens, webhook secrets,
signing keys, and model provider keys as scoped governance resources.

#### Scenario: Credential is registered
- **WHEN** a credential or token is registered
- **THEN** the system must record owner, organization, applicable scopes,
  provider or tool, allowed capabilities, sensitivity label, lifecycle state,
  rotation metadata, revocation metadata, and audit trail without exposing the
  secret value as normal product data

#### Scenario: Credential is selected for use
- **WHEN** an agent, integration, service account, system job, or human action
  needs to use a credential
- **THEN** authorization must evaluate the credential scope, requested
  capability, actor principal, resource sensitivity, organization policy,
  and approval requirements

### Requirement: Secret Value Separation
Office Graph SHALL separate secret values from product metadata and protect
them through a dedicated secret-storage strategy.

#### Scenario: Secret metadata is stored
- **WHEN** product tables store credential, token, key, or webhook-secret
  metadata
- **THEN** those tables must store references, fingerprints, status, scope,
  and policy metadata rather than plaintext secret values

#### Scenario: Secret value is accessed
- **WHEN** runtime code retrieves or uses a secret value
- **THEN** the access must be authorized, auditable when policy-sensitive, and
  scoped to the specific tool, integration, or external action

### Requirement: SecretStore Boundary
Office Graph SHALL access secret values through a dedicated SecretStore
boundary rather than binding product domains to a specific cloud or vault
provider.

#### Scenario: SaaS customer registers an integration credential
- **WHEN** a customer supplies a credential for Office Graph to use in the
  managed SaaS product
- **THEN** Office Graph may store the secret value in an Office
  Graph-managed secret backend while storing only metadata, references,
  fingerprints, versions, scope, lifecycle, rotation, and revocation data in
  product tables

#### Scenario: Enterprise customer requires customer-managed secrets
- **WHEN** a customer requires selected secret values to remain in their own
  AWS, GCP, Azure, Vault, or equivalent keystore
- **THEN** Office Graph must preserve a design path to retrieve or use only the
  approved secrets through narrow delegated access, such as workload identity,
  federated access, external identifiers, short-lived credentials, or
  provider-native delegation

#### Scenario: Customer-managed keystore access is configured
- **WHEN** Office Graph is granted access to a customer-managed keystore
- **THEN** the access must be scoped to approved secrets and capabilities
  rather than broad long-lived access to the customer's entire keystore

### Requirement: Webhook Sources As Principals
Office Graph SHALL register webhook sources as principals with explicit trust,
scope, event, and verification policy.

#### Scenario: Webhook event is received
- **WHEN** Office Graph receives a webhook event
- **THEN** the system must authenticate the source, evaluate the registered
  webhook-source principal, validate allowed event types and scopes, and route
  the event through integration adapters and domain actions

#### Scenario: Webhook event is replayed
- **WHEN** a webhook event is replayed or retried
- **THEN** the system must preserve source identity, idempotency key or
  equivalent replay identity, tenant scope, and audit or sync-event
  traceability

### Requirement: External Write Controls
Office Graph SHALL govern external writes separately from graph read/write
access.

#### Scenario: External write is requested
- **WHEN** a principal attempts to post an external comment, push an external
  change, modify a provider record, trigger a provider workflow, or call a
  write-capable provider API
- **THEN** authorization must evaluate external-write capability, integration
  scope, credential scope, resource sensitivity, approval requirements,
  related work packet policy, and related run when applicable

#### Scenario: Agent can read graph context
- **WHEN** an agent can read graph context related to an external system
- **THEN** that read permission must not imply permission to use provider write
  credentials or perform external writes

### Requirement: Credential Rotation And Revocation
Office Graph SHALL track credential rotation and revocation as governed,
auditable lifecycle events.

#### Scenario: Credential is rotated
- **WHEN** a credential is rotated
- **THEN** the system must preserve prior credential metadata, new credential
  metadata, actor, reason when available, affected integrations, affected
  scopes, timestamp, and audit trail

#### Scenario: Credential is revoked
- **WHEN** a credential is revoked
- **THEN** the system must prevent future use, preserve revocation actor and
  reason when available, and make affected agent runs, integrations, and
  external actions fail closed or require reauthorization
