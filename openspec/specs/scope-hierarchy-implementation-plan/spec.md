# scope-hierarchy-implementation-plan Specification

## Purpose
Define ownership and sequencing for implementing the tenant scope hierarchy.
## Requirements
### Requirement: Scope Hierarchy Implementation Ownership
Office Graph SHALL plan scope hierarchy implementation as an
authorization-owned fact model coordinated through operation correlation and
public bounded-context contracts.

#### Scenario: Scope hierarchy implementation is planned
- **WHEN** future backend implementation work introduces authorization scope
  resources, parent relationships, closure rows, hierarchy repairs, or
  inheritance-mode changes
- **THEN** the plan MUST identify the owning authorization, operation
  correlation, audit, revision, projection, and realtime contracts before
  code or migrations are generated

#### Scenario: Cross-context scope workflow is planned
- **WHEN** a scope hierarchy command needs operation correlation, audit
  evidence, revision history, authorization decisions, or projection
  invalidation
- **THEN** the workflow MUST use public context interfaces rather than writing
  another context's private tables directly

### Requirement: Typed Scope Row Planning
Office Graph SHALL plan authorization scopes as typed organization-bound facts
with concrete ownership references and lifecycle state.

#### Scenario: Scope row schema is planned
- **WHEN** the first authorization scope migration is designed
- **THEN** the plan MUST define organization ownership, stable scope identity,
  scope type, direct parent scope when present, lifecycle state, owning bounded
  context, operation provenance, and allowed assignment or grant behavior

#### Scenario: Scope target reference is planned
- **WHEN** a scope row corresponds to a workspace, initiative, workstream,
  department, org unit, team, component, repository, service, integration,
  external source, artifact, or resource
- **THEN** the plan MUST use concrete foreign keys, scope-type-specific
  extension rows, graph identity, or another approved typed reference pattern
  rather than an unbounded local `resource_type` plus `resource_id` target
  model for Office Graph-owned records

#### Scenario: Scope type registry is planned
- **WHEN** implementation defines supported scope types
- **THEN** the plan MUST define rootability, allowed parent and child scope
  types, lifecycle constraints, visibility-scope behavior, assignment and
  grant eligibility, sensitivity-inheritance eligibility, and owning context
  for each supported type

### Requirement: Closure Row Planning
Office Graph SHALL plan closure rows as durable scope path facts that support
efficient authorization checks, explanation, repair, and projection
invalidation.

#### Scenario: Closure row schema is planned
- **WHEN** the first authorization scope path migration is designed
- **THEN** the plan MUST define ancestor scope, descendant scope, depth,
  lifecycle state, path inheritance eligibility or blockage, provenance,
  operation correlation, and hierarchy or fact-version anchors needed for
  explanation and invalidation

#### Scenario: Scope path is used for authorization explanation
- **WHEN** an authorization decision relies on descendant scope inheritance
- **THEN** the implementation plan MUST preserve enough closure-row identity
  or fact-version information to explain the original assignment or grant,
  ancestor scope, descendant scope, path basis, capability, and inheritance
  mode

#### Scenario: String path shortcut is proposed
- **WHEN** implementation planning proposes `ltree`, materialized string
  paths, wildcard permission strings, or string-prefix matching for primary
  permission inheritance
- **THEN** the plan MUST reject that shortcut unless a later accepted change
  explicitly preserves typed scope rows, closure-row explanation, and
  operation-correlated move semantics as the primary authority basis

### Requirement: Inheritance Mode Planning
Office Graph SHALL plan path inheritance and authorization-fact inheritance as
separate inputs interpreted by the policy boundary.

#### Scenario: Role assignment or grant inheritance is planned
- **WHEN** a role assignment, explicit grant, or sensitivity assignment can
  apply beyond its assigned scope
- **THEN** the plan MUST define the fact's descendant inheritance mode and how
  it combines with eligible closure paths before inherited authority or
  sensitivity can affect a descendant resource

#### Scenario: Closure path blocks inherited authority
- **WHEN** a scope path exists for hierarchy, projection, or organization
  structure but is not eligible for permission inheritance
- **THEN** authorization MUST NOT treat that path as an inherited permission
  basis even when the ancestor has role assignments or grants

#### Scenario: Inheritance mode changes
- **WHEN** a scope path, role assignment, grant, or sensitivity assignment
  changes inheritance behavior
- **THEN** the plan MUST treat the change as an operation-correlated fact
  change that can affect authorization explanation, durable decision records,
  graph projections, and derived caches

### Requirement: Closure Rebuild And Repair Planning
Office Graph SHALL plan closure rebuilds and repairs as controlled
maintenance workflows rather than disposable cache refreshes.

#### Scenario: Closure drift is detected
- **WHEN** maintenance detects missing, stale, duplicate, cross-tenant,
  impossible, or lifecycle-invalid closure rows
- **THEN** the repair plan MUST compare closure rows with direct parentage,
  produce a bounded diff or repair summary, and repair affected rows through an
  operation-correlated maintenance workflow

#### Scenario: Repair changes effective inherited authority
- **WHEN** closure repair changes effective inherited authority, sensitivity
  inheritance, or projection membership
- **THEN** the repair workflow MUST publish the same authorization explanation
  and projection invalidation hints required for an equivalent scope move

#### Scenario: Bulk repair requires direct SQL
- **WHEN** a closure rebuild or repair path is too broad for normal Ash
  actions
- **THEN** the plan MAY use direct Ecto or SQL only when it remains
  context-owned, tenant-scoped, operation-correlated, audited when required,
  tested, and covered by the same invalidation semantics as normal scope
  commands
