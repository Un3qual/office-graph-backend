# extension-table-rules Specification

## Purpose
TBD - created by archiving change design-persistence-model. Update Purpose after archive.
## Requirements
### Requirement: Extension Table Justification
Office Graph SHALL introduce provider-specific, source-specific, or
department-specific extension tables only when shared base resources cannot
cleanly represent required behavior.

#### Scenario: Provider-specific field is proposed
- **WHEN** a source-specific field, constraint, lifecycle state, API behavior,
  webhook semantic, sync cursor, or reconciliation rule does not fit the
  provider-neutral base table
- **THEN** the design MUST use an extension table linked to the base resource
  instead of adding vague nullable columns to the shared table

### Requirement: Extension Tables Preserve Base Identity
Office Graph extension tables SHALL depend on provider-neutral base resources
for shared identity, scope, state, and graph participation.

#### Scenario: Extension row is created
- **WHEN** a GitHub, GitLab, Sentry, design-tool, marketing-tool, or finance
  extension row is stored
- **THEN** it MUST reference the base resource row and MUST NOT become a second
  source of truth for tenant scope, graph identity, lifecycle state, or shared
  provider-neutral fields

### Requirement: Extension Tables Are Revisited
Office Graph SHALL revisit extension tables when provider-specific behavior
becomes shared product behavior.

#### Scenario: Extension behavior becomes common
- **WHEN** a field or behavior introduced for one provider becomes useful
  across multiple providers or native Office Graph workflows
- **THEN** a later persistence change MUST promote it into the provider-neutral
  model or a shared typed resource
