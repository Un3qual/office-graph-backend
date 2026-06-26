## ADDED Requirements

### Requirement: Principal Role Capability Facts
Office Graph SHALL store principals, roles, capabilities, role memberships,
assignments, and grants as typed authorization facts.

#### Scenario: Role grants capabilities
- **WHEN** a system or custom role is defined
- **THEN** it MUST have organization ownership where applicable, lifecycle
  state, stable role identity, and typed role-capability memberships rather
  than JSON policy blobs

#### Scenario: Role is assigned
- **WHEN** a principal receives a role
- **THEN** the role assignment MUST record target principal, role, assigned
  scope, descendant inheritance mode, actor, reason when available, lifecycle
  state, and operation correlation
- **AND** authorization MUST treat the assigned role as effective only within
  the role's owning organization

#### Scenario: Explicit grant is created
- **WHEN** exceptional access is granted
- **THEN** the explicit grant MUST record principal, resource or scope,
  capability, reason, creator, optional expiration, lifecycle state, and
  operation correlation

### Requirement: Organization Structure Policy Facts
Office Graph SHALL model organization structure as authorization facts when
policy depends on it.

#### Scenario: Group is imported from an external provider
- **WHEN** an IdP group, SCIM group, provider group, or customer role is mapped
  into Office Graph
- **THEN** the mapping MUST target internal teams, role assignments, custom
  roles, grants, scopes, or capabilities instead of treating the external name
  as direct product authority

#### Scenario: Approver eligibility is computed
- **WHEN** policy resolves eligible approvers, managers, owners, team leads, or
  separation-of-duties constraints
- **THEN** it MUST be able to use typed team, membership, group mapping,
  department, org unit, ownership, manager, and data-owner facts

#### Scenario: Ownership relationship changes
- **WHEN** a manager, owner, data owner, team lead, or resource steward
  relationship is created, changed, or removed
- **THEN** the relationship MUST be stored as a typed lifecycle fact with
  organization, applicable scope or resource, actor, reason when available,
  and operation correlation

### Requirement: Sensitivity Labels As Authorization Facts
Office Graph SHALL represent resource sensitivity with typed labels and
assignments separate from visibility scopes.

#### Scenario: Sensitive resource is labeled
- **WHEN** a resource is marked normal, confidential, secret, source code,
  customer-sensitive, finance-sensitive, legal-sensitive, or
  security-sensitive
- **THEN** the sensitivity assignment MUST record resource, label, inheritance
  basis when applicable, actor, lifecycle state, and operation correlation

#### Scenario: Visibility policy is evaluated
- **WHEN** a graph projection or authorization check evaluates visibility
- **THEN** visibility MUST come from tenant/scope and projection policy while
  sensitivity labels influence redaction, approval, audit, export, AI context,
  and credential-use policy
