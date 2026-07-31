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

### Requirement: Local development identity fixtures are deterministic

Office Graph SHALL provide an explicit idempotent development setup that
creates and reconciles the fixed identity, external-link, role, assignment,
and lifecycle facts used by the local authentication chooser.

#### Scenario: Developer seeds local identities

- **WHEN** a developer runs `mix demo.seed` in development
- **THEN** Office Graph MUST reconcile fixed owner, workspace-administrator,
  member, and deprovisioned-member fixtures in the seeded organization and
  workspace through Ash-backed setup actions
- **AND** each chooser fixture MUST have a stable server-owned selector key and
  expected identity basis without exposing its database ID to the browser

#### Scenario: Development seed is replayed

- **WHEN** `mix demo.seed` is rerun with the same fixture manifest
- **THEN** it MUST NOT create duplicate principals, profiles, external identity
  links, roles, role-capability memberships, role assignments, policy bundles,
  or active sessions
- **AND** it MUST preserve the intentionally disabled lifecycle of the
  deprovisioned fixture

#### Scenario: Fixture role assignments drift outside the manifest

- **WHEN** a manifest-owned local fixture principal has acquired a role
  assignment other than its one expected assignment and the developer reruns
  `mix demo.seed`
- **THEN** the explicit seed action MUST remove the unexpected assignment
  through Ash and restore the exact manifest-owned assignment set for that
  fixture

#### Scenario: Browser reaches login before seeding

- **WHEN** local authentication is enabled but the required development
  fixtures have not been seeded
- **THEN** the chooser or selection response MUST instruct the developer to run
  `mix demo.seed` and MUST NOT invoke bootstrap or fixture reconciliation from
  the request pipeline

### Requirement: Local role fixtures exercise real authorization differences

Office Graph SHALL assign the local chooser fixtures ordinary scoped roles and
capabilities so development requests exercise current authorization behavior
instead of a fixture-only bypass.

#### Scenario: Developer selects different active fixtures

- **WHEN** the developer signs in as owner, workspace administrator, or member
- **THEN** the resulting sessions MUST produce distinct authorization outcomes
  from ordinary role, capability, scope, and policy facts
- **AND** the chooser MUST NOT place role names or capabilities into the browser
  session as trusted authority

#### Scenario: Development role profiles are inspected

- **WHEN** a developer or test inspects the seeded workspace-administrator and
  member profiles
- **THEN** their capability sets MUST come from one typed development fixture
  catalog and MUST distinguish organization administration, workspace
  operation, ordinary participation, and read access
- **AND** the catalog MUST state that it is development fixture policy rather
  than the final production default-role contract

#### Scenario: Deprovisioned fixture retains historical authority facts

- **WHEN** the deprovisioned fixture has retained role assignments from its
  prior active state
- **THEN** its disabled principal or external identity lifecycle MUST still
  prevent session issuance and authorization while preserving those historical
  facts
