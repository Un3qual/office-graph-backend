# bootstrap-and-local-identity-lab Specification

## Purpose
Define safe first-organization bootstrap and local identity-lab behavior for development environments.
## Requirements
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

### Requirement: Explicit Bootstrap Is Not Request Authentication

Office Graph SHALL keep first-owner bootstrap as an explicit controlled action
and SHALL NOT invoke it to authenticate normal product or API requests.

#### Scenario: Unauthenticated product request arrives

- **WHEN** a request without a valid human session reaches a product page
- **THEN** Office Graph MUST redirect the browser to the configured login path
  and MUST NOT create or assign a local owner

#### Scenario: Unauthenticated API request arrives

- **WHEN** a request without a valid human session reaches GraphQL or the JSON
  API
- **THEN** Office Graph MUST leave the request without a human actor and MUST
  NOT invoke local-owner bootstrap

#### Scenario: Test or development fixture needs an owner

- **WHEN** a test or developer explicitly invokes the local bootstrap helper
- **THEN** the existing idempotent first-owner fixture behavior MAY create or
  return the controlled local owner and session outside the normal request
  pipeline

### Requirement: Authentik Login Configuration Is Explicit

Office Graph SHALL enable the local Authentik OIDC path only from a complete,
explicit provider configuration.

#### Scenario: OIDC configuration is missing or partial

- **WHEN** a human attempts login without a complete issuer, client, and
  account-linking configuration
- **THEN** login MUST fail closed and MUST NOT fall back to local-owner
  bootstrap
