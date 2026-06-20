## ADDED Requirements

### Requirement: Non-Human Credential Mechanics
Office Graph SHALL define issuance, verification, rotation, and revocation
mechanics for non-human principals.

#### Scenario: Service account credential is issued
- **WHEN** a service account receives a credential
- **THEN** Office Graph MUST record owner principal or owning organization,
  allowed scopes, allowed capabilities, issue/expiry metadata, SecretStore
  reference, fingerprint, lifecycle state, and operation/audit linkage through
  credential metadata

#### Scenario: Webhook source proves identity
- **WHEN** a webhook event is received
- **THEN** Office Graph MUST authenticate the webhook source principal, verify
  the allowed provider/source/event scope, and reject or quarantine events that
  fail verification

#### Scenario: Integration installation acts
- **WHEN** an integration installation calls a provider API or receives an
  event
- **THEN** Office Graph MUST evaluate installation principal, credential scope,
  requested capability, resource sensitivity, and operation context before
  accepting the action or using the credential

### Requirement: Agent Credentials Are Run-Scoped
Office Graph SHALL avoid modeling agent authority as broad user sessions.

#### Scenario: Internal agent run starts
- **WHEN** an internal agent run starts
- **THEN** the run MUST carry an agent principal, delegator or trigger
  authority basis, autonomy envelope, allowed scopes/tools/sensitivity labels,
  and any temporary grants approved by policy

#### Scenario: External executor acts for Office Graph
- **WHEN** an external executor performs delegated work
- **THEN** Office Graph MUST authenticate the executor principal, constrain
  credentials to the approved work packet or run scope, and preserve audit and
  operation correlation for credential use
