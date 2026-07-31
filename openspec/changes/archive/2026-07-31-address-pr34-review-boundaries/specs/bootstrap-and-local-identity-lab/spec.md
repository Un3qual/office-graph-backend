## MODIFIED Requirements

### Requirement: Local development identity fixtures are deterministic

Office Graph SHALL provide an explicit idempotent development setup that creates and reconciles the fixed identity, external-link, role, assignment, and lifecycle facts used by the local authentication chooser.

#### Scenario: Developer seeds local identities

- **WHEN** a developer runs `mix demo.seed` in development
- **THEN** Office Graph MUST reconcile fixed owner, workspace-administrator, member, and deprovisioned-member fixtures in the seeded organization and workspace through Ash-backed setup actions
- **AND** each chooser fixture MUST have a stable server-owned selector key and expected identity basis without exposing its database ID to the browser

#### Scenario: Development seed is replayed

- **WHEN** `mix demo.seed` is rerun with the same fixture manifest
- **THEN** it MUST NOT create duplicate principals, profiles, external identity links, roles, role-capability memberships, role assignments, policy bundles, or active sessions
- **AND** it MUST preserve the intentionally disabled lifecycle of the deprovisioned fixture

#### Scenario: Fixture role assignments drift outside the manifest

- **WHEN** a manifest-owned local fixture principal has acquired a role assignment other than its one expected assignment and the developer reruns `mix demo.seed`
- **THEN** the explicit seed action MUST remove the unexpected assignment through Ash and restore the exact manifest-owned assignment set for that fixture

#### Scenario: Browser reaches login before seeding

- **WHEN** local authentication is enabled but the required development fixtures have not been seeded
- **THEN** the chooser or selection response MUST instruct the developer to run `mix demo.seed` and MUST NOT invoke bootstrap or fixture reconciliation from the request pipeline
