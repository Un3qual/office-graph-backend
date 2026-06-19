## ADDED Requirements

### Requirement: Enterprise Identity Integration Posture
Office Graph SHALL include enterprise identity integration posture in the MVP
architecture for SSO, OIDC, SAML, identity-provider group mapping, and external
identity links.

#### Scenario: Identity model is designed
- **WHEN** users, principals, memberships, roles, or groups are modeled
- **THEN** the design must preserve a path to map external identity-provider
  users and groups into Office Graph principals, memberships, and scoped roles

#### Scenario: SSO user logs in
- **WHEN** a user authenticates through SSO, OIDC, or SAML
- **THEN** Office Graph must be able to reconcile the login to an existing
  principal through external identity links, verified identifiers, or explicit
  account-linking policy

#### Scenario: SSO claims include groups or roles
- **WHEN** SSO claims include groups, roles, departments, or other customer
  identity attributes
- **THEN** Office Graph must map those claims into internal teams, custom
  roles, scoped assignments, or grants rather than treating external claim
  names as direct product permissions

### Requirement: SCIM Provisioning Posture
Office Graph SHALL include SCIM-compatible provisioning, deprovisioning, and
group synchronization in the MVP identity architecture.

#### Scenario: User lifecycle is modeled
- **WHEN** user and principal lifecycle state is designed
- **THEN** it must support external provisioning, suspension,
  deprovisioning, group mapping, membership removal, and audit of identity
  lifecycle events

#### Scenario: Deprovisioned user owns work
- **WHEN** a SCIM or identity-provider event deprovisions a user who
  owns graph items, packets, credentials, approvals, runs, or integrations
- **THEN** Office Graph must preserve historical provenance while preventing
  unauthorized future access

#### Scenario: SCIM group membership changes
- **WHEN** a SCIM client adds or removes a user from an external group
- **THEN** Office Graph must update the mapped team membership, scoped role
  assignment, custom role, or grant according to configured mapping policy and
  record the provisioning event

#### Scenario: SCIM payload conflicts with local state
- **WHEN** SCIM data conflicts with an existing user, principal, group,
  external identity link, role mapping, or membership
- **THEN** Office Graph must resolve the conflict through deterministic import
  policy, error reporting, or an admin review state rather than silently
  creating ambiguous identities

### Requirement: Local Identity Lab
Office Graph SHALL support local SSO and SCIM development without requiring a
paid hosted enterprise IdP.

#### Scenario: Developer tests enterprise identity locally
- **WHEN** a developer needs to test SSO login, SCIM provisioning, group
  mapping, deprovisioning, or identity reconciliation
- **THEN** the project must provide or plan a local identity-lab path using
  self-hosted authentik as the primary OIDC/SAML/SCIM fixture, optional
  Keycloak for OIDC/SAML compatibility, and a repo-owned fake SCIM client for
  deterministic contract tests

#### Scenario: CI tests SCIM behavior
- **WHEN** SCIM provisioning behavior is tested in CI
- **THEN** the tests must be able to run through a deterministic fake SCIM
  client without depending on paid Entra, Okta, or another hosted vendor

#### Scenario: Vendor compatibility is needed
- **WHEN** Okta, Entra, or another hosted IdP compatibility needs to be checked
- **THEN** those checks may run as optional smoke tests and must not be
  required for normal local development or CI

### Requirement: SCIM Contract Coverage
Office Graph SHALL define SCIM contract tests for provisioning edge cases
before relying on vendor-specific integration testing.

#### Scenario: Fake SCIM client runs contract tests
- **WHEN** the repo-owned fake SCIM client tests Office Graph
- **THEN** it must cover user create, user update, user deactivate, group
  create, group rename, group delete, membership add, membership remove,
  duplicate external identifiers, invalid payloads, and PATCH add, remove, and
  replace behavior

#### Scenario: SSO and SCIM identities reconcile
- **WHEN** the same person logs in through SSO and is provisioned through SCIM
- **THEN** Office Graph must reconcile both flows to one principal according
  to external identity link and account-linking policy

### Requirement: SIEM And Audit Export Posture
Office Graph SHALL preserve a path to SIEM and compliance export without
making audit records product-only logs.

#### Scenario: Audit schema is designed
- **WHEN** audit, authorization decision, credential use, external write, or
  agent tool-use records are designed
- **THEN** their shape must support later tenant-scoped export with stable
  action names, principal references, resource references, timestamps,
  outcomes, and correlation identifiers

#### Scenario: SIEM export is added later
- **WHEN** SIEM export is implemented in a future change
- **THEN** it must be able to export policy-approved audit records without
  exposing secrets, restricted payloads, or unauthorized sensitive content

### Requirement: Enterprise Admin Surfaces
Office Graph SHALL plan governance concepts so future enterprise admin
surfaces can manage them without bypassing domain policy.

#### Scenario: Admin manages governance
- **WHEN** an admin later manages roles, grants, classifications, AI provider
  policy, credentials, integrations, retention, legal hold, or audit export
- **THEN** those actions must go through the same domain authorization,
  revision, and audit boundaries as non-admin product actions

#### Scenario: Admin visibility is restricted
- **WHEN** an admin views governance data that references secrets, sensitive
  artifacts, source code, finance data, legal data, customer data, or security
  records
- **THEN** the admin surface must enforce classification and audit visibility
  policy rather than assuming all admins can see all payloads

### Requirement: Initial Enterprise Integration Priority
Office Graph SHALL prioritize enterprise governance integrations without
adding Linear or full workflow-system replacement to the initial planning
slice.

#### Scenario: Governance integration order is planned
- **WHEN** enterprise governance integrations are prioritized
- **THEN** SSO/OIDC/SAML posture, SCIM posture, SIEM export posture,
  local identity-lab testing, GitHub/GitLab organization governance, and
  Slack/Teams notification or approval surfaces must be considered before
  broad workflow-tool replacement

#### Scenario: Existing external software is integrated
- **WHEN** Office Graph integrates with external enterprise software
- **THEN** the integration must be treated as an adoption ramp, signal source,
  or action target while preserving a path to graph-native Office Graph
  workflows where they are materially better
