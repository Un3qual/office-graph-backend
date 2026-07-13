# tenant-scope-indexing Specification

## Purpose
Define explicit tenant and scope columns and indexes for scoped data access.
## Requirements
### Requirement: Explicit Tenant And Scope Columns
Office Graph SHALL store tenant and work scope explicitly where authorization,
filtering, indexing, export, retention, or deletion requires it.

#### Scenario: Tenant-owned record is stored
- **WHEN** a durable tenant-owned record is created
- **THEN** it MUST carry organization scope directly unless it is strictly
  owned by an immutable parent path that cannot cross organizations

#### Scenario: Scope is needed for queries
- **WHEN** workspace, initiative, workstream, team, component,
  repository, integration, external source, artifact, or resource scope affects
  authorization, filtering, indexing, export, or retention
- **THEN** the durable record MUST store or safely inherit that scope through a
  strict, queryable ownership path

### Requirement: Baseline Index Families
Office Graph SHALL define baseline index families from expected tenant,
workflow, graph, external-source, and event query shapes.

#### Scenario: Table is introduced
- **WHEN** a table is added for a durable product, graph, integration, event,
  revision, or audit concept
- **THEN** its design MUST evaluate foreign-key indexes, organization and
  status indexes, scope indexes, graph edge source/type and target/type
  indexes, external identifier uniqueness, soft-delete partial uniqueness, and
  time-range indexes where applicable

### Requirement: Soft-Delete-Aware Uniqueness
Office Graph SHALL account for soft deletion when defining uniqueness rules.

#### Scenario: Active record display identifier can be reused
- **WHEN** display names, labels, or non-URL user-facing identifiers can be
  reused after product deletion
- **THEN** uniqueness MUST be enforced with active-record semantics such as
  partial indexes while preserving deleted-row history

#### Scenario: URL-bearing slug is reserved
- **WHEN** a URL-bearing slug or handle has ever identified a resource within
  an organization and scope
- **THEN** uniqueness MUST reserve that slug or handle beyond product deletion
  so old URLs never resolve to a different new resource

#### Scenario: Provider identifier is imported
- **WHEN** a provider external identifier is stored for reconciliation
- **THEN** uniqueness MUST generally remain stable per organization, source,
  object type, and external identifier even if the local resource is deleted
