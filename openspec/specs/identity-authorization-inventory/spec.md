# identity-authorization-inventory Specification

## Purpose
TBD - created by archiving change design-identity-and-authorization-schema. Update Purpose after archive.
## Requirements
### Requirement: Identity Authorization Schema Inventory
Office Graph SHALL maintain a concrete relational table-family inventory for
identity, authorization, organization facts, sensitivity, policy facts, and
credential metadata before first backend migrations are generated.

#### Scenario: First migration inventory is planned
- **WHEN** the first backend migration scope is selected
- **THEN** it MUST account for principals, principal profiles, external
  identity links, authorization scopes, scope paths, capabilities, roles, role
  capabilities, role assignments, explicit grants, team/group/department/org
  unit policy facts, sensitivity labels, sensitivity assignments, policy bundle
  versions, policy component versions, authorization decision records,
  authorization fact versions when needed, manager/owner/data-owner facts, and
  credential metadata as typed relational concepts

#### Scenario: Persistence design references authorization facts
- **WHEN** the persistence model names identity or authorization resources
- **THEN** it MUST reference this inventory as the owning schema design rather
  than duplicating subtly different table requirements

### Requirement: Principal Profile Separation
Office Graph SHALL keep generic principal actor records separate from human
profile and display data.

#### Scenario: Human user is represented
- **WHEN** a human actor is stored
- **THEN** the generic principal record MUST carry policy-relevant actor state
  while human display name, avatar, contact preferences, and profile details
  live in a profile table or equivalent typed companion resource

#### Scenario: Non-human actor is represented
- **WHEN** an agent, service account, integration installation, webhook source,
  external executor, or system job is stored
- **THEN** it MUST be represented as a principal without requiring fake human
  profile fields

### Requirement: External Identity Links
Office Graph SHALL store external identity mappings as provider-neutral,
auditable links from external subjects to internal principals.

#### Scenario: External identity is linked
- **WHEN** an OIDC, SAML, SCIM, IdP, provider, or external executor identity is
  linked to Office Graph
- **THEN** the link MUST record provider, provider tenant, external subject,
  verified identifier when available, account-linking state, lifecycle state,
  conflict state, owning organization, and operation/audit provenance

#### Scenario: External identity conflicts
- **WHEN** two external records claim the same internal principal or verified
  identifier incompatibly
- **THEN** Office Graph MUST preserve conflict state and require an explicit
  reconciliation action before trusting the link for authorization
