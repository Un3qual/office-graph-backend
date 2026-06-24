## ADDED Requirements

### Requirement: Governed Scope Move Command Planning
Office Graph SHALL plan scope moves as governed domain commands, not as direct
updates to a parent scope column.

#### Scenario: Scope move command is planned
- **WHEN** future implementation work defines a command to move a scope under
  a different parent
- **THEN** the plan MUST validate organization tenancy, scope lifecycle, source
  scope type, target parent type, root-scope constraints, cycle rules, policy
  authority, and applicable retention or legal-hold blockers before any
  hierarchy mutation is committed

#### Scenario: Direct parent update is proposed
- **WHEN** implementation planning proposes updating direct parentage without
  the governed scope move command
- **THEN** the plan MUST reject that path for product behavior because it
  bypasses closure recalculation, operation correlation, audit, revision,
  authorization decision, and projection invalidation requirements

#### Scenario: Move would create a cycle or tenant crossing
- **WHEN** the requested new parent is the scope itself, a descendant of the
  scope, owned by another organization, or incompatible with the scope type
- **THEN** the move MUST fail before direct parentage or closure rows are
  changed

### Requirement: Scope Move Operation Idempotency
Office Graph SHALL plan idempotency and causal tracing for scope move
commands.

#### Scenario: Scope move is attempted
- **WHEN** a principal, agent, service account, integration, system job, or
  maintenance workflow requests a scope move
- **THEN** the command MUST create or reuse an operation correlation record
  with organization, relevant scopes, actor or authority basis, command key,
  idempotency key when available, request or trace identifiers, source
  surface, reason when available, and timestamps

#### Scenario: Scope move is retried
- **WHEN** the same idempotency basis is retried with the same source scope,
  old parent, new parent, actor or authority basis, and command semantics
- **THEN** Office Graph MUST return or reference the existing operation result
  instead of creating a second hierarchy mutation

#### Scenario: Idempotency key is reused with different inputs
- **WHEN** a caller reuses a scope move idempotency key for a different scope,
  parent, actor, authority basis, or command semantics
- **THEN** Office Graph MUST reject the request as an idempotency conflict
  before hierarchy state changes

### Requirement: Scope Move Closure Update Planning
Office Graph SHALL plan scope move closure updates as one consistent hierarchy
mutation with direct parentage.

#### Scenario: Scope move succeeds
- **WHEN** a scope move passes validation and authorization
- **THEN** the command MUST update direct parentage, supersede or lifecycle
  old affected closure rows, insert new affected closure rows, preserve
  operation provenance, and compute affected authority and sensitivity impact
  in one approved transaction boundary where those records apply

#### Scenario: No-op move is requested
- **WHEN** a scope is moved to its current parent with the same effective
  hierarchy semantics
- **THEN** Office Graph MUST treat the request as a no-op or idempotent
  command without rewriting closure rows or emitting misleading audit and
  revision records

#### Scenario: Scope move cannot complete closure updates
- **WHEN** direct parentage changes but closure updates, operation records,
  required audit records, or required invalidation records cannot be persisted
- **THEN** the command MUST fail atomically or leave the hierarchy in a state
  that a documented repair workflow can detect before new authorization
  decisions rely on it

### Requirement: Scope Move Audit Revision And Decision Planning
Office Graph SHALL plan separate operation, audit, revision, and authorization
decision records for scope moves.

#### Scenario: Scope move changes hierarchy
- **WHEN** a scope move changes direct parentage or effective inherited
  authority
- **THEN** the plan MUST create or be able to create an operation correlation
  record, authorization decision record when policy requires it, durable audit
  event, and typed revision or scope-history record without using any one of
  those record families as a substitute for the others

#### Scenario: Scope move audit event is written
- **WHEN** a successful, denied, escalated, or approval-gated scope move is
  audit-sensitive
- **THEN** the audit plan MUST include an action key, result vocabulary,
  actor/delegation context, moved scope target, old parent target, new parent
  target, operation correlation, policy or decision reference when applicable,
  reason when available, and redacted impact summary suitable for customer
  audit projection

#### Scenario: Scope move revision is written
- **WHEN** a scope move changes product hierarchy state
- **THEN** the revision plan MUST preserve the moved scope, old parent, new
  parent, operation correlation, actor or source, reason when available,
  affected hierarchy version or fact anchor, and enough typed before/after
  information to reconstruct the meaningful hierarchy change

#### Scenario: Scope move decision is recorded
- **WHEN** authorization denies, redacts, escalates, approval-gates, or
  durably records a policy-sensitive scope move
- **THEN** the decision record MUST reference the effective policy bundle,
  relevant fact versions or anchors, requested move, result, authority basis,
  matched rule or obligation reference when available, operation correlation,
  and request or trace identifier

### Requirement: Scope Move Repair And Compensation Planning
Office Graph SHALL plan recovery from failed, incorrect, or superseded scope
moves through governed repair or compensating commands.

#### Scenario: Incorrect move must be undone
- **WHEN** an authorized administrator or maintenance workflow needs to undo a
  completed scope move
- **THEN** Office Graph MUST plan a compensating scope move or repair command
  with its own operation correlation, authorization checks, audit evidence,
  revision records, closure updates, and invalidation hints

#### Scenario: Repair is caused by a previous operation
- **WHEN** closure repair, hierarchy correction, or compensation is triggered
  by a previous scope move, migration, backfill, or incident
- **THEN** the repair operation MUST preserve causal references without merging
  the repair payload into the original operation
