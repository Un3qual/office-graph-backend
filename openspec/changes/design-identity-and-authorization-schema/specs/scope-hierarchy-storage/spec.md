## ADDED Requirements

### Requirement: Scope Hierarchy Storage
Office Graph SHALL store authorization scope hierarchy with direct parentage
and explicit closure rows for inherited scope paths.

#### Scenario: Scope is created
- **WHEN** an organization, workspace, initiative, workstream, department, org
  unit, team, component, repository, service, integration, external source,
  artifact, or resource scope is created
- **THEN** the system MUST store a typed scope row and the closure rows needed
  to identify ancestor scope, descendant scope, depth, inheritance mode,
  lifecycle state, provenance, and operation correlation

#### Scenario: Descendant permission is explained
- **WHEN** an authorization decision relies on inherited scope authority
- **THEN** the explanation MUST identify the assignment or grant, original
  scope, inherited descendant scope, closure path basis, capability, and
  inheritance mode

### Requirement: Scope Move Domain Action
Office Graph SHALL treat moving a scope as a governed operation-correlated
domain action.

#### Scenario: Scope is moved
- **WHEN** a scope moves under a different parent
- **THEN** Office Graph MUST validate tenant, type, cycle, and policy rules;
  update direct parentage; recalculate affected closure rows; record
  before/after inheritance impact; and link the move to operation correlation
  and audit provenance

#### Scenario: Authorization explanations are cached
- **WHEN** a scope move changes inherited authority or sensitivity inheritance
- **THEN** affected cached authorization explanations MUST be invalidated or
  recomputed before they can be used for new decisions

### Requirement: No String Path Permission Semantics
Office Graph SHALL NOT use string path matching as the primary permission
inheritance model.

#### Scenario: Wildcard-like scope access is needed
- **WHEN** a role assignment or grant should apply to descendants
- **THEN** Office Graph MUST represent that through typed scope rows,
  descendant inheritance settings, and closure rows rather than `ltree`,
  materialized path, or wildcard strings as the sole policy basis
