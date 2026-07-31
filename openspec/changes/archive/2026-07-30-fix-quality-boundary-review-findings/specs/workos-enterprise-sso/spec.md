## ADDED Requirements

### Requirement: Organization-wide mapped identities enter a selected workspace

Office Graph SHALL allow an active organization-wide external group-role
mapping to satisfy a trusted preferred workspace in the same organization
while retaining workspace-bound human sessions.

#### Scenario: Organization-wide mapped member completes WorkOS login

- **WHEN** the transaction-bound WorkOS connection selects a workspace and the
  reconciled principal has only an active organization-wide mapping for that
  organization
- **THEN** Office Graph MUST resolve the preferred workspace, issue its own
  workspace-bound session, and validate that session against the inherited
  organization authority

#### Scenario: Organization-wide mapping belongs to another organization

- **WHEN** the preferred workspace scope names an organization different from
  the active organization-wide mapping
- **THEN** the mapping MUST NOT satisfy login scope selection or session
  validation
