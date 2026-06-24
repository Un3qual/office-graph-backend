## Context

Office Graph already requires typed hierarchical authorization scopes,
descendant inheritance, explainable authorization decisions, operation
correlation, durable audit records, typed revisions, and
authorization-filtered graph projections. The accepted identity and
authorization design defines the table families for `authorization_scopes` and
`authorization_scope_paths`; the revision/audit design owns operation
correlation, audit envelopes, authorization decision records, and typed
revision separation; the code-organization design owns bounded-context
contracts; and the accepted graph projection specs require projection
filtering, explanation, and cache invalidation.

This change is the implementation-planning bridge between those accepted
requirements. It does not reopen the product decision to use typed scope rows
and closure rows. It defines how future implementation changes must plan the
scope hierarchy write path, move semantics, repair behavior, and derived-state
invalidation before migrations or code are generated.

## Goals / Non-Goals

**Goals:**

- Define planning requirements for typed scope rows, closure rows, lifecycle,
  inheritance modes, and scope hierarchy ownership.
- Define scope move semantics as governed domain commands with tenant, type,
  cycle, lifecycle, policy, idempotency, and operation-correlation checks.
- Define how scope moves create audit, revision, authorization decision, and
  operation records without collapsing those record families into one event.
- Define closure rebuild and repair posture for drift, backfills, and
  maintenance without making direct parent updates a normal product path.
- Define invalidation requirements for authorization explanations, graph
  projections, render caches, work packet context, and realtime subscribers.
- Keep code and migration work deferred to later implementation changes.

**Non-Goals:**

- No Phoenix, Ash, Ecto, migration, Oban, GraphQL, JSON API, React, or runtime
  code.
- No final column list, index list, migration ordering, lock strategy, job
  module, resolver shape, or UI design.
- No replacement for the accepted authorization, audit/revision,
  code-organization, persistence, realtime, or graph projection specs.
- No policy-rule redesign. This change plans how scope hierarchy facts are
  stored, moved, repaired, and invalidated; policy bundles still interpret
  those facts.

## Decisions

### 1. Authorization owns scope truth; operations own command trace

`OfficeGraph.Authorization` should own authorization scope resources, direct
parentage, closure rows, inheritance-mode interpretation inputs, and
authorization explanation facts. `OfficeGraph.Operations` should own operation
context, idempotency basis, and durable operation correlation. Scope creation,
move, inheritance-mode changes, and repair commands cross those contexts
through public APIs rather than direct table access.

The future migration plan should keep direct parentage as the source of truth
for the current hierarchy and closure rows as derived-but-durable facts used
for efficient checks and explainable decisions. Closure rows are durable
because decisions may cite them; they are still repairable from direct
parentage plus operation history when drift is detected.

Alternatives considered:

- **Let each resource own its own scope path:** This duplicates inheritance
  logic across teams, repositories, initiatives, integrations, and artifacts.
- **Put scope movement under graph relationships:** Graph edges do not grant
  access, so graph relationship ownership would blur the access boundary.
- **Make operations own scope tables:** Operation correlation is the command
  trace, not the authorization fact owner.

### 2. Scope rows must be typed and concrete enough for ownership

The implementation plan should treat each authorization scope as a typed fact
within an organization. A future schema may use concrete foreign keys,
scope-type-specific extension rows, or an approved typed envelope tied to
graph identity, but it must not introduce an unbounded local
`resource_type`/`resource_id` shortcut for Office Graph-owned records.

The scope-type registry should define allowed parent/child combinations,
rootability, whether the scope participates in visibility, whether it may
carry inherited sensitivity labels, whether it may receive role assignments or
grants, and which owning bounded context controls lifecycle transitions. The
registry is an implementation-planning artifact first; exact seed data can be
chosen by the first migration change.

Alternatives considered:

- **Generic type/id target columns:** Easy to start, but conflicts with the
  code-organization rule for concrete references and makes referential
  integrity weak.
- **One nullable foreign key per possible scope owner on the base table:** Very
  explicit, but it may become unwieldy. The later migration plan can choose
  this only where the concrete scope set is small enough.
- **String paths only:** Rejected by accepted requirements because permission
  inheritance must be typed and explainable.

### 3. Distinguish path inheritance from assignment inheritance

Closure rows should describe the hierarchy path: ancestor, descendant, depth,
path lifecycle, path provenance, operation correlation, and the path's
inheritance eligibility or blockage. Role assignments, explicit grants,
sensitivity assignments, and future policy facts should separately record how
that fact applies to descendants, such as scope-only, all eligible
descendants, or policy-approved descendant type sets.

Authorization should allow inherited authority only when both sides agree: the
fact's inheritance mode permits descendant use and the closure path is eligible
for that kind of inheritance. This prevents a role assignment from accidentally
crossing into a scope type where the path exists for organization structure or
projection context but does not carry permission inheritance.

Alternatives considered:

- **Store one inheritance mode only on assignments:** Too weak for blocked
  paths, scope-type changes, and future hierarchy repair explanations.
- **Store all policy meaning on closure rows:** Makes closure rows act like
  policy rules instead of facts interpreted by policy bundles.

### 4. Scope moves are single governed commands, not parent-id updates

A scope move should be planned as one domain command that validates tenant,
scope type, lifecycle state, parent compatibility, cycle rules, policy,
legal/retention blockers when applicable, and operation idempotency before
state changes. The command should update direct parentage, close or supersede
old affected closure rows, insert new closure rows, record affected
inheritance and sensitivity impact, and emit invalidation hints in one
approved transaction boundary where the applicable records are written.

The command should reject no-op or duplicate retries through idempotency rules.
If the same idempotency basis is retried with the same move inputs, callers can
receive the existing operation result. If the key is reused with different
move inputs, the command must fail rather than create a second hierarchy
mutation.

Alternatives considered:

- **Directly update `parent_scope_id`:** Fast, but bypasses audit, revision,
  closure recalculation, authorization explanation invalidation, and cycle
  protection.
- **Model moves as delete/recreate:** Breaks durable identity, URL tokens,
  audit continuity, graph references, and historical decision explanation.
- **Use asynchronous closure recalculation only:** Creates windows where new
  authorization checks can use stale hierarchy facts.

### 5. Scope moves write separate operation, audit, revision, and decision records

A successful scope move should create or reuse an operation correlation record
with actor, command key, idempotency key, authority basis, reason, source, and
request/trace identifiers. It should create authorization decision records
when policy requires durable evidence, audit events for policy-sensitive
administrative behavior, and typed revision or scope-history records for the
scope hierarchy change. Audit targets should include concrete references for
the moved scope, old parent, new parent, and any impacted high-level scope
families that are safe to disclose.

These records should reference one another by operation or explicit links
where needed, but none of them should copy another record family's payload.
Historical authorization decisions should continue to reference the policy and
fact versions that were effective when the decision was made.

Alternatives considered:

- **One scope_move_events table as the only history:** Easier to query for this
  one action, but it would replace the accepted separation among operations,
  audit, revisions, and authorization decisions.
- **Audit only the direct parent change:** Misses inherited permission impact,
  sensitivity changes, and projection invalidation evidence.

### 6. Closure repair is a controlled maintenance workflow

Future implementation should include a closure repair or rebuild workflow, but
it must be scoped, explainable, and operation-correlated. A repair plan should
compare direct parentage to closure rows, detect missing, stale, duplicate, or
impossible paths, produce a dry-run diff or bounded repair summary, and then
rewrite affected closure rows through an approved maintenance command. Repair
work must publish the same invalidation hints as an equivalent scope move when
effective inherited authority or sensitivity changes.

Bulk repair may use direct Ecto or SQL if the implementation plan explains why
normal Ash actions are inappropriate. That direct path still needs tenant,
scope, operation, audit, authorization, and invalidation safeguards.

Alternatives considered:

- **Treat closure rows as disposable cache:** Too weak because authorization
  explanations and sensitive decisions may cite specific path facts.
- **Never repair, only migrate forward:** Unrealistic once backfills,
  maintenance, or future scope-type changes exist.

### 7. Invalidation is part of the write plan

Every hierarchy mutation that changes effective inherited authority,
sensitivity inheritance, or visibility scope must invalidate or mark stale the
derived state that depends on those facts. This includes authorization
explanation caches, authorization-filtered projection read models, UI/render
caches, work packet context packages, agent context packages, and realtime
subscribers.

The invalidation signal should include enough identity and version information
for the projection or cache owner to reconcile through an authorized read:
operation id, affected organization, affected ancestor and descendant scopes,
scope hierarchy version or fact-version anchor, and whether authority,
sensitivity, or projection membership may have changed. It should not carry
sensitive payloads or grant access by itself.

Alternatives considered:

- **Let projections discover stale scope facts lazily:** Simpler writes, but
  creates inconsistent agent context and UI caches after permission-changing
  moves.
- **Broadcast full recomputed projection payloads:** Risks leaking data and
  duplicates projection logic in realtime delivery.

## Risks / Trade-offs

- [Risk] Closure rows add write amplification for scope moves. Mitigation:
  keep moves as governed administrative commands, compute affected subtrees
  precisely, and defer broad hierarchy read models until volume proves need.
- [Risk] Cached explanations or projections can leak stale authority after a
  move. Mitigation: version hierarchy facts and require invalidation before
  stale derived state can serve new decisions.
- [Risk] A generic scope target model would be faster to implement. Mitigation:
  require the first migration change to choose concrete references or an
  approved typed envelope rather than an unbounded polymorphic shortcut.
- [Risk] Repair jobs can bypass normal authorization semantics. Mitigation:
  model repair as operation-correlated maintenance with bounded scope, audit
  evidence, dry-run summaries, and equivalent invalidation.
- [Risk] Impact calculation may be expensive for large subtrees. Mitigation:
  plan indexes, subtree bounds, affected-scope summaries, and asynchronous
  projection rebuilds while keeping the authoritative hierarchy mutation
  transactionally consistent.

## Migration Plan

This design does not create migrations. Later implementation changes should
sequence work roughly as follows:

1. Define the scope-type registry, ownership contracts, operation keys,
   audit-action keys, and test fixtures.
2. Add migrations for typed scope rows, direct parentage, closure rows,
   hierarchy/fact versioning anchors, and indexes.
3. Add governed create/move/inheritance-mode commands with idempotency,
   operation correlation, authorization checks, closure updates, audit, and
   revisions.
4. Add closure repair and rebuild tooling with dry-run output and
   operation-correlated repair records.
5. Add invalidation contracts for authorization explanations, graph
   projections, work packet/agent context, render caches, and realtime
   subscribers.
6. Add backfill and verification checks before any product surface relies on
   inherited scope authority.

Rollback for future implementation should be planned as compensating hierarchy
operations or repair commands, not as ad hoc database rewrites. A failed
projection rebuild should leave durable scope truth intact and mark derived
state stale until it is safely rebuilt.

## Open Questions

- Which initial scope types need descendant role assignment support in the
  first migration, and which should be hierarchy-only until product workflows
  require inheritance?
- Which authorization explanation caches are needed in v1 versus recomputing
  explanations from scope paths and fact rows?
- Should closure rows carry a global hierarchy version, per-scope version, or
  both for cache invalidation and fact-version anchors?
- Which scope move impact summaries are safe for ordinary admins versus
  security/audit operators?
