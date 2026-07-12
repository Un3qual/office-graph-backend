# credential-metadata-model Specification

## Purpose
Define secret-free credential metadata that supports governance without persisting credential material.
## Requirements
### Requirement: Secret-Free Credential Metadata
Office Graph SHALL store credential metadata as product data while keeping
secret values behind a SecretStore boundary.

#### Scenario: Credential metadata is registered
- **WHEN** an integration credential, tool token, webhook secret, signing key,
  model provider key, service account credential, or external executor
  credential is registered
- **THEN** product tables MUST record provider, owner principal, organization,
  lifecycle state, fingerprint or external reference, secret-store
  key/reference, rotation metadata, revocation metadata, last-used/audit
  linkage, sensitivity, and audit/operation linkage without storing the
  plaintext secret value

#### Scenario: Credential has scoped authority
- **WHEN** a credential is valid only for selected scopes or capabilities
- **THEN** Office Graph MUST represent allowed scopes and allowed capabilities
  through typed rows or normalized joins rather than unqueryable JSON lists

#### Scenario: Credential is used
- **WHEN** a human, agent, service account, integration, webhook source, system
  job, or external executor uses a credential
- **THEN** authorization MUST evaluate actor principal, requested capability,
  credential scope, resource sensitivity, organization policy, approval
  requirements, and operation context before secret access or external use

### Requirement: Credential Lifecycle Audit Linkage
Office Graph SHALL link credential lifecycle changes to operation correlation
and audit records.

#### Scenario: Credential is rotated
- **WHEN** a credential is rotated
- **THEN** Office Graph MUST preserve prior metadata, new metadata, actor,
  reason when available, affected scopes/integrations/runs, timestamp, and
  operation/audit linkage

#### Scenario: Credential is revoked
- **WHEN** a credential is revoked
- **THEN** future use MUST fail closed or require reauthorization, and the
  revocation MUST preserve actor, reason when available, affected scopes,
  affected principals, and operation/audit linkage
