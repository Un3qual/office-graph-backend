## ADDED Requirements

### Requirement: Local development identity fixtures are deterministic

Office Graph SHALL provide an explicit idempotent development setup that
creates the fixed identity, external-link, role, assignment, and lifecycle
facts used by the local authentication chooser.

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
