## ADDED Requirements

### Requirement: First Organization Bootstrap
Office Graph SHALL provide a controlled bootstrap path for the first
organization and first organization owner before hosted enterprise identity is
configured.

#### Scenario: Empty system is bootstrapped
- **WHEN** Office Graph has no organization owner
- **THEN** bootstrap MUST be able to create the first organization, first org
  owner principal, principal profile, first workspace, seeded system roles and
  capabilities, initial policy bundle version, and first owner session or
  invitation handoff

#### Scenario: Bootstrap is rerun in development or test
- **WHEN** development or test bootstrap is rerun with the same fixture inputs
- **THEN** it MUST be idempotent and MUST NOT create duplicate organizations,
  owners, workspaces, roles, capabilities, or policy bundles

#### Scenario: Bootstrap is attempted after owner exists
- **WHEN** production bootstrap is attempted after the first owner has been
  established
- **THEN** it MUST be disabled or tightly controlled through a separate
  recovery/break-glass process and MUST preserve audit evidence

### Requirement: Local Identity Lab Fixture Coverage
Office Graph SHALL plan local identity fixtures that cover enterprise identity
and non-human principal edge cases without hosted IdP dependency.

#### Scenario: Local identity lab is run
- **WHEN** a developer exercises the identity lab locally
- **THEN** it MUST include authentik as the primary OIDC/SAML/SCIM fixture,
  optional Keycloak compatibility, and seeded org owner, workspace admin,
  member, deprovisioned user, duplicate verified identifier, group mapping
  conflict, service account, webhook source, and agent principal scenarios

#### Scenario: CI exercises SCIM contracts
- **WHEN** CI tests provisioning behavior
- **THEN** it MUST be able to use a deterministic repo-owned fake SCIM client
  for user create/update/deactivate, group create/rename/delete, membership
  add/remove, duplicate external identifiers, invalid payloads, and PATCH add,
  remove, and replace behavior
