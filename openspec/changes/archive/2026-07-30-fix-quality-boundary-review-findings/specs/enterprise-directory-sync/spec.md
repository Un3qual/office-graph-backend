## ADDED Requirements

### Requirement: Organization-wide mapping management preserves explicit scope

Office Graph SHALL distinguish an omitted management workspace from an
explicitly organization-wide external group-role mapping and SHALL require
authority at the target scope before persistence.

#### Scenario: Authorized administrator creates an organization-wide mapping

- **WHEN** an administrator with organization-scoped
  `enterprise_identity.manage` authority explicitly creates a mapping with no
  workspace
- **THEN** the authorized management action MUST persist `workspace_id: nil`
  rather than replacing it with the administrator's session workspace

#### Scenario: Organization-wide mapping lifecycle changes

- **WHEN** an administrator explicitly targets an existing organization-wide
  mapping for disablement or another supported lifecycle transition
- **THEN** Office Graph MUST require organization-scoped management authority,
  update the nil-scoped record, and leave workspace-scoped mappings unchanged

#### Scenario: Workspace authority targets organization-wide scope

- **WHEN** an administrator has management authority only in the current
  workspace and explicitly targets organization-wide scope
- **THEN** Office Graph MUST reject the create or lifecycle mutation

#### Scenario: Workspace connection cannot back an organization-wide mapping

- **WHEN** an organization-authorized administrator targets organization-wide
  scope for a group owned by a workspace-scoped enterprise connection
- **THEN** Office Graph MUST reject the mapping instead of widening the
  connection's directory authority
