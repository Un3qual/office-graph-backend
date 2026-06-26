# Architecture Stabilization Decision Questions

## Purpose

This document collects the decisions that need owner input before or during the
`stabilize-architecture-foundation` implementation. The first section contains
the questions that can block meaningful refactor work. Later sections contain
questions that can be answered while guardrails, inventories, and low-risk
module moves are underway.

Each question includes:

- **Decision needed:** the concrete choice to make.
- **Why it matters:** what the decision controls.
- **Context:** what the current plan or code shape implies.
- **Options:** reasonable choices and trade-offs.
- **When needed:** the point in implementation where the answer becomes
  blocking.

## Already Locked

These decisions are recorded in the proposal/design/specs and do not need to be
answered again unless the architecture direction changes.

- GraphQL and JSON API code stay under `OfficeGraphWeb`, not separate root
  application namespaces.
- GraphQL and JSON API code use separate folders and module namespaces:
  `OfficeGraphWeb.GraphQL.*` / `lib/office_graph_web/graphql/` and
  `OfficeGraphWeb.JsonApi.*` / `lib/office_graph_web/json_api/`.
- API folders use transport first, capability second, purpose third.
- Shared API helper modules remain transport-specific under that transport's
  `common` namespace.
- Domain behavior, command ownership, and projection contracts belong under
  `OfficeGraph.*`, not under `OfficeGraphWeb`.
- The first implementation batch should add guardrails and inventories before
  broad refactors.

## Blocking Before Major Refactor Work

### 1. Where should strict AshJsonApi be mounted during migration?

**Decision needed:** Choose the path that hosts generated AshJsonApi surfaces
while existing manual `/api` compatibility endpoints remain live.

**Why it matters:** The mount path determines whether generated JSON API
behavior is treated as the durable public JSON API, a temporary migration
surface, or a versioned future contract. It also affects tests, frontend
adapters, documentation, and compatibility endpoint retirement.

**Context:** The current `/api` namespace is manual Phoenix controller code.
Generated AshJsonApi will likely have stricter resource routing, payload shape,
relationship shape, error behavior, and action exposure rules than the existing
walking-skeleton JSON endpoints.

**Options:**

- Keep generated AshJsonApi under existing `/api`.
  This is the most direct path, but it risks mixing compatibility endpoints
  with stricter generated resource contracts.
- Mount generated AshJsonApi under `/api/v1`.
  This creates an explicit durable version boundary, but it may imply all
  current manual endpoints are also versioned before we are ready.
- Mount generated AshJsonApi under temporary `/jsonapi`.
  This cleanly separates migration/parity work from compatibility behavior, but
  it is less polished as a final public URL.

**When needed:** Before task 2.8 mounts AshJsonApi reads.

**Follow-up answer needed:** If the answer is `/jsonapi`, decide what event
promotes or redirects it to the durable path.

### 2. Which transport should the operator console dogfood first?

**Decision needed:** Choose whether the operator console keeps JSON as its
default data adapter until projections stabilize, or switches to GraphQL once a
generated schema is available.

**Why it matters:** The frontend projection-client boundary can hide JSON vs
GraphQL from components, but only one transport will be the main feedback loop.
That choice influences which API receives earlier parity work and which
transport problems surface first.

**Context:** The current operator UI already consumes JSON endpoints. GraphQL
is currently manual and will be modularized before generated AshGraphql reads
are introduced. Switching too early could force frontend churn while backend
contracts are still moving.

**Options:**

- Keep JSON as the default adapter until operator projections stabilize.
  This minimizes frontend churn and preserves current smoke value.
- Switch to GraphQL as soon as generated reads/projections are available.
  This dogfoods the future API earlier, but may pull frontend work into backend
  schema churn.
- Support both adapters behind the projection client and choose per route or
  test.
  This is useful for parity tests, but it can overcomplicate the first frontend
  cleanup if treated as product behavior.

**When needed:** Before task 4.6 locks frontend adapter contract tests, and
before API parity work decides which transport is canonical for operator reads.

**Follow-up answer needed:** Define the switch condition if JSON remains the
default for now.

### 3. Which boundary owns packet-run-verification orchestration?

**Decision needed:** Name the public domain command boundary that owns the
workflow currently coordinated through `OfficeGraph.ApiSupport`.

**Why it matters:** This command spans packet readiness, run creation,
observations, evidence, verification checks, operation correlation, idempotency,
authorization, and audit/revision side effects. Without one owner, each API
transport or wrapper module will keep duplicating lifecycle logic.

**Context:** The stabilization plan says transport code must load context, call
an owning command, and map errors. It must not own transaction choreography,
validation, idempotency, lifecycle transitions, or audit behavior.

**Options:**

- `OfficeGraph.WorkPackets`.
  Fits packet preparation/readiness, but may overextend the packet context into
  run and verification lifecycle ownership.
- `OfficeGraph.Runs`.
  Fits execution attempts and observations, but may make packet creation and
  verification result recording feel secondary.
- `OfficeGraph.Verification`.
  Fits evidence/check decisions, but the workflow starts earlier than
  verification.
- New `OfficeGraph.WorkExecution`.
  Creates a clear owner for the cross-domain execution workflow, but introduces
  a new context that needs a tight charter.
- `OfficeGraph.OperatorWorkflow`.
  Matches the current product-facing use case, but risks making a UI projection
  boundary own domain lifecycle unless carefully scoped.

**When needed:** Before tasks 2.10, 2.11, and 3.8 move orchestration out of
`OfficeGraph.ApiSupport`.

**Follow-up answer needed:** Define allowed dependencies, transaction boundary,
idempotency key basis, authorization contract, and projection read contract for
the chosen owner.

### 4. Should packet readiness be backend-projected as a command affordance?

**Decision needed:** Choose whether packet readiness input should come from a
backend projection now, or whether the frontend can keep a documented temporary
adapter that assembles command input from current projection records.

**Why it matters:** If the UI builds command input from graph links and raw
relationship types, frontend code becomes a second domain model. If the backend
projects readiness affordances, the UI renders allowed actions and submits a
stable input shape.

**Context:** The UI projection specs already require command affordances for
actions such as preparing packets, starting runs, accepting evidence, and
completing verification. The current UI pressure exists before the backend has
those affordance projections.

**Options:**

- Project packet readiness affordances from the backend now.
  This is cleaner and reduces frontend inference, but expands backend work in
  the first cleanup batch.
- Keep a temporary frontend adapter with explicit retirement criteria.
  This limits backend churn while decomposing the UI, but keeps known debt live.
- Block packet readiness UI refactor until backend projection support lands.
  This avoids a temporary adapter, but delays frontend cleanup.

**When needed:** Before task 4.7 removes or isolates frontend-derived packet
readiness command assembly.

**Follow-up answer needed:** If a temporary adapter stays, define the exact
backend projection shape that will replace it.

### 5. How aggressive should the `proposed_graph_changes` vocabulary migration be?

**Decision needed:** Choose whether to rename code/storage immediately or
translate to canonical "Change Proposal" terminology at API/UI boundaries first.

**Why it matters:** This controls migration risk. A storage/code rename touches
database schema, resource modules, tests, API fields, projections, and frontend
types. API/UI translation is smaller but leaves legacy language in internals.

**Context:** The concept simplification plan says "Change Proposal" is the
user-facing product term for proposed mutations. It also says legacy storage
names may remain temporarily if new API/UI layers translate them.

**Options:**

- Rename code and storage now.
  This removes the old term quickly, but creates a wide migration before the
  architecture is stable.
- Translate API/UI now and rename storage later.
  This protects user-facing vocabulary while keeping the refactor smaller.
- Keep the old term everywhere until a broader model cleanup.
  This avoids immediate churn, but contradicts the stabilization goal of
  stopping legacy vocabulary from spreading.

**When needed:** Before tasks 5.3 and 5.4 update product vocabulary and
proposal checklist guidance.

**Follow-up answer needed:** Define whether compatibility aliases are required
for GraphQL fields, JSON API fields, frontend types, or fixtures.

## API Surface Decisions

### 6. Which generated Ash resource reads should come first?

**Decision needed:** Choose the first WorkGraph, WorkPackets, Runs, and/or
Verification resources to expose through generated AshGraphql/AshJsonApi reads.

**Why it matters:** The first generated reads will set conventions for action
exposure, authorization checks, relationship shape, pagination, error shape,
and parity tests.

**Context:** The plan says generated reads come before generated lifecycle
writes. Current manual APIs include compatibility commands and projections that
span more than one bounded context, so not every endpoint should become a
generated resource read.

**Options:**

- Start with simple read-only resources that have low lifecycle risk.
- Start with resources needed by the operator console projection.
- Start with resources that already declare AshGraphql/AshJsonApi extensions.
- Start with resources whose manual endpoints are easiest to retire.

**When needed:** Before task 2.6 selects the first read surfaces.

### 7. What is the API parity standard during migration?

**Decision needed:** Define what "parity" means when manual compatibility
endpoints and generated/custom replacement APIs overlap.

**Why it matters:** Some parity should be exact, such as authorization and
idempotency. Other parity may intentionally differ, such as JSON API envelope
shape or GraphQL field naming. Without a standard, tests can either overfit the
old API or fail to protect important behavior.

**Context:** The specs require equivalent authorization behavior, operation
context, validation errors, idempotency semantics, durable state changes, and
safe structured error shapes where compatibility is promised.

**Options:**

- Exact response-shape parity for compatibility endpoints only.
- Behavioral parity for generated replacements, with transport-native envelope
  differences allowed.
- Field-by-field compatibility aliases during migration.

**When needed:** Before generated API tests are written in task 2.9.

### 8. What structured error contract should each transport own?

**Decision needed:** Define which stable error fields are shared semantically
and which are transport-specific presentation details.

**Why it matters:** GraphQL errors and JSON API errors should not be forced into
one shape, but they should carry consistent codes, safe details, and operation
context. If this is undefined, error mapping will keep being duplicated or
transport-inappropriate.

**Context:** The locked module organization keeps `OfficeGraphWeb.GraphQL`
common helpers separate from `OfficeGraphWeb.JsonApi` common helpers. Domain
commands should return stable domain errors that each transport maps.

**Options:**

- Shared domain error struct plus transport-specific mappers.
- Separate transport error modules that agree only on stable error codes.
- Compatibility-first errors now, stricter generated errors later.

**When needed:** Before task 2.4 extracts transport-specific error mapping.

### 9. Which manual endpoints are durable custom command/projection exceptions?

**Decision needed:** Identify which current manual GraphQL fields, JSON routes,
serializers, and projection endpoints should remain custom rather than being
replaced by generated Ash API surfaces.

**Why it matters:** The compatibility ledger needs an owner, reason,
replacement target, parity tests, and retirement condition for every manual
surface that remains live.

**Context:** Custom transport code remains valid for cross-domain commands,
policy-filtered mixed projections, webhooks, integrations, and temporary
compatibility paths. It is not valid as a default resource API pattern.

**Options:**

- Treat only cross-domain commands as durable custom APIs.
- Treat mixed operator projections as durable custom APIs too.
- Treat everything manual as temporary until proven otherwise.

**When needed:** During tasks 1.2, 1.3, and 2.12.

### 10. Which generated writes, if any, are safe for public exposure?

**Decision needed:** Decide whether any Ash creates/updates should be publicly
generated in the near term, or whether all lifecycle-driving writes remain
behind domain commands for now.

**Why it matters:** Accidentally exposing private lifecycle actions through
AshGraphql or AshJsonApi would make it possible to bypass the intended command
owner, audit behavior, idempotency rules, or authorization checks.

**Context:** The current plan says generated reads come first and private
lifecycle actions stay private unless a later spec explicitly makes them safe.

**Options:**

- No generated public writes during stabilization.
- Allow only simple administrative/reference-data writes with explicit specs.
- Allow resource writes once each owning domain has action-level lifecycle
  contracts and tests.

**When needed:** Before any generated mutation/write route is added.

## Domain And Ash Decisions

### 11. Which architecture exception ledger entries should burn down first?

**Decision needed:** Prioritize direct Ecto, raw SQL, broad `authorize?: false`,
manual transaction, and transport-owned orchestration exceptions.

**Why it matters:** The first burn-down target determines where tests and
domain action cleanup go first. It should reduce the most harmful drift without
breaking current smoke value.

**Context:** The plan treats the exception ledger as a burn-down contract, not
steady-state architecture. Touching code covered by an exception should narrow
or retire that exception when possible.

**Options:**

- Burn down transport-owned orchestration first.
- Burn down broad authorization bypasses first.
- Burn down direct Ecto writes first.
- Burn down whichever exception is touched by the first API/frontend cleanup.

**When needed:** During task 1.2 inventory and before the first domain cleanup
stage.

### 12. Who owns evidence acceptance and run/check recomputation?

**Decision needed:** Choose the command owner for evidence acceptance,
verification result recording, required-check satisfaction, and run-state
recomputation.

**Why it matters:** These actions cross WorkGraph, Runs, Verification, and
possibly WorkPackets. If each context partially owns the workflow, state can
drift or duplicate validation rules.

**Context:** Task 3.8 calls this out explicitly. The answer may be the same as
the packet-run-verification owner or a narrower Verification-owned command.

**Options:**

- Use the same cross-domain command boundary chosen for packet-run-verification.
- Make Verification own evidence acceptance and result recording.
- Make Runs own recomputation and required-check satisfaction.
- Split ownership but require one public facade command.

**When needed:** Before task 3.8.

### 13. Which raw UUID references should become modeled Ash relationships first?

**Decision needed:** Choose the first resource cluster where raw UUID reference
fields should be promoted into relationships.

**Why it matters:** Relationship modeling affects generated API shape,
authorization filters, preload behavior, tests, and whether resources can be
read safely through AshGraphql/AshJsonApi.

**Context:** Task 3.1 names graph item, signal, task, review finding,
verification check, artifact, evidence item, evidence candidate, and
verification result as early candidates.

**Options:**

- Start with WorkGraph resources that feed operator projections.
- Start with WorkPackets resources because packet readiness depends on them.
- Start with Runs/Verification resources because execution state is most
  cross-cutting.

**When needed:** Before task 3.1 implementation.

### 14. Which validations move into Ash actions first?

**Decision needed:** Choose the invariant group to consolidate first:
open-state checks, same-scope checks, graph-item checks, packet readiness,
required-check validation, run/check state transitions, or evidence acceptance.

**Why it matters:** Duplicated validation between wrappers and Ash changes is a
major source of drift. The first consolidation should have tight regression
coverage and clear ownership.

**Context:** Tasks 3.3, 3.5, and 3.7 all require moving stable invariants into
one action/change location per invariant.

**Options:**

- Start with WorkGraph open-state/same-scope invariants.
- Start with WorkPackets packet readiness invariants.
- Start with Runs/check transition invariants.
- Start with evidence/verification invariants.

**When needed:** Before first domain cleanup implementation after inventories.

### 15. Which map/json fields must become queryable product data?

**Decision needed:** Classify map/json payload fields as raw/debug metadata,
temporary compatibility payload, or durable product-queryable data.

**Why it matters:** Product-queryable data should not stay hidden inside maps if
it drives API fields, filters, authorization, operator decisions, or reports.
Raw/debug data can stay flexible.

**Context:** Task 3.9 names `RunEvent.payload`, `ProposedGraphChange.payload`,
`EvidenceItem.visibility_constraints`, and similar fields.

**Options:**

- Keep event payloads raw/debug unless a projection needs them.
- Promote visibility constraints because authorization/projection logic may
  depend on them.
- Translate proposed change payloads at API/UI first, then revisit storage.
- Define a promotion checklist for any payload field used in filters or
  operator-facing decisions.

**When needed:** Before task 3.9 and before generated reads expose these fields.

## Frontend Decisions

### 16. How much routing should exist before a second real product route?

**Decision needed:** Decide whether the frontend should introduce a minimal
router now, URL-selected inbox row behavior only, or defer broader routing until
another accepted product route exists.

**Why it matters:** Routing can clarify state and test boundaries, but inert
routes and nav items can create fake product surface area. The plan currently
leans minimal until there is a second real route.

**Context:** The operator console is the first product UI. The frontend needs
decomposition, projection hooks, and app-shell verification more urgently than
full navigation.

**Options:**

- Keep only `/operator` and local selection state.
- Add URL selection for the current operator inbox row.
- Add a minimal React router with only implemented routes.
- Add broader nav scaffolding with unavailable affordances for planned routes.

**When needed:** Before task 4.8.

### 17. When should a query/cache layer be introduced?

**Decision needed:** Decide whether to introduce query/cache infrastructure
during the operator console cleanup or wait until multiple routes/realtime
invalidation require it.

**Why it matters:** A query/cache layer solves deduplication, cancellation,
staleness, refetching, and error state. Adding it too early can overbuild the
first rescue; adding it too late can leave fetch logic scattered.

**Context:** The design says to add a query cache once more than one route or
realtime invalidation exists.

**Options:**

- Defer query/cache until a second route or realtime invalidation.
- Add a lightweight in-feature fetch hook now with no third-party cache.
- Add a full query/cache library during the frontend foundation work.

**When needed:** Before task 4.5/4.6 if data hooks start sharing server state.

### 18. What is the minimum design/component system scope?

**Decision needed:** Define the initial shared tokens and primitives that are
allowed before a broader design system exists.

**Why it matters:** The current frontend started without a concrete component
system. The goal is enough consistency to stop sprawl, not a large design
platform that slows down product work.

**Context:** Task 4.1 and 4.2 name concept tokens, badge, button, panel, pane
header, nav rail, text field, and empty/error state. Shared components must not
embed operator-specific domain mapping.

**Options:**

- Lock only the named primitives for the first batch.
- Add table/list, tabs, modal, tooltip, and form-field primitives now.
- Keep shared components extremely generic and put all workflow mapping in
  feature modules.

**When needed:** Before task 4.1/4.2 implementation.

### 19. Which frontend test stack is authoritative?

**Decision needed:** Choose the project-local frontend verification command and
test tools that CI/local development should use.

**Why it matters:** The current plan calls out frontend verification problems:
local dependencies must be used, the system TypeScript compiler must not be
accidentally used, the app must build, and Phoenix app-shell asset references
must be verified.

**Context:** Frontend cleanup should not proceed if verification is ambiguous.
The app shell currently references built assets, so verification must prove the
build can produce what Phoenix serves.

**Options:**

- Keep a single `npm run verify` command and fix it to use project-local tools.
- Split typecheck, unit/component tests, build, and app-shell asset checks.
- Add a Mix task that runs frontend verification through the Nix shell.

**When needed:** Before tasks 1.6, 1.7, 4.9, and 4.10.

## Product Concept Decisions

### 20. Which planned concepts are MVP-facing now?

**Decision needed:** Decide whether any planned concepts should be promoted to
default operator-facing MVP scope instead of staying backend/internal or future
scope.

**Why it matters:** Every product noun that becomes public affects API fields,
UI labels, projections, docs, authorization, tests, and migration burden. The
stabilization plan intentionally keeps the first product spine small.

**Context:** The canonical MVP spine is Signal, Change Proposal, Work Item,
Work Packet, Run, Check, Evidence, and Verification.

**Concepts to explicitly accept or defer:**

- Questions.
- Decisions.
- Rich text quote snapshots.
- SCIM group mapping.
- Explicit grants.
- Agent executions.
- Graph conversations.
- Provider-specific review objects.
- Evidence candidate as a separate product concept.
- Operation correlation as a visible operator concept.

**When needed:** Before task 5.7 adds proposal checklist guidance and before
new UI/API contracts introduce any of these terms.

### 21. How should infrastructure details appear in operator projections?

**Decision needed:** Define what belongs in default operator fields versus
trace/debug/audit fields.

**Why it matters:** Infrastructure records are valuable for troubleshooting and
compliance, but exposing them as primary product nouns makes the UI harder to
understand and locks implementation mechanics into public contracts.

**Context:** The plan says records such as GraphItem, GraphRelationship,
OperationCorrelation, RawArchive, ExecutionObservation, EvidenceCandidate,
VerificationResult, PolicyBundle, audit records, and revisions are hidden by
default.

**Options:**

- Default projection contains only product-spine fields.
- Add a nested `trace` or `debug` object for authorized internal surfaces.
- Keep audit/compliance projections separate from operator workflow
  projections.

**When needed:** Before task 5.5 and before UI projection contracts are updated.

### 22. Should EvidenceCandidate remain internal or become Evidence with state?

**Decision needed:** Decide whether suggested evidence should appear as
Evidence with states such as suggested/accepted/rejected/stale, or whether
EvidenceCandidate is a distinct operator-facing concept.

**Why it matters:** A separate EvidenceCandidate product noun adds UI and API
complexity. Modeling it as Evidence with state keeps the workflow simpler but
may hide important review mechanics if operators need to act on candidates
directly.

**Context:** The concept simplification spec says EvidenceCandidate is internal
unless an accepted workflow requires operators to review suggested evidence
directly.

**Options:**

- Model candidates as Evidence with explicit state in API/UI projections.
- Keep EvidenceCandidate entirely internal and show only accepted Evidence.
- Promote EvidenceCandidate as a separate review queue concept.

**When needed:** Before tasks 5.6 and 3.8.

## Governance And Sequencing Decisions

### 23. What is allowed during stabilization without opening a new exception?

**Decision needed:** Define the threshold for narrow bug fixes, small UI fixes,
manual API edits, and domain changes while stabilization is incomplete.

**Why it matters:** The plan says narrow bug fixes may proceed, but they must
not copy unstable patterns into new product surface area. The boundary between
"narrow fix" and "new exception" should be explicit.

**Context:** Architecture drift gates will fail when new manual API surfaces,
direct DB paths, broad authorization bypasses, or frontend sprawl appear
without accepted documentation.

**Options:**

- Allow only behavior-preserving fixes without new public API/UI surface.
- Allow narrow manual API edits if covered by an existing ledger entry.
- Require every new route/field/screen/domain exception to update OpenSpec.

**When needed:** Before stabilization guard tests are added in tasks 1.4 and
1.5.

### 24. Which checks become required gates locally and in CI?

**Decision needed:** Decide the authoritative command set for stabilization
verification.

**Why it matters:** The plan is only useful if drift is caught by commands.
Some checks may be local-only at first; others should be CI gates immediately.

**Context:** The current tasks mention OpenSpec validation,
`mix architecture.conformance`, frontend verification, focused API/frontend
tests, app-shell asset checks, and `git diff --check`.

**Options:**

- Require all gates locally before each stabilization commit.
- Add only OpenSpec and architecture conformance first, then expand.
- Separate quick local gates from full CI gates.

**When needed:** Before task 1.8 and final handoff checks.

### 25. How should compatibility endpoint retirement be approved?

**Decision needed:** Define the evidence required before a manual GraphQL/JSON
compatibility endpoint can be removed, redirected, or demoted.

**Why it matters:** Removing compatibility endpoints too early can break the
operator console and smoke flows. Leaving them forever turns the compatibility
ledger into permanent debt.

**Context:** The architecture-stabilization spec requires replacement behavior,
frontend client behavior, authorization semantics, and structured error
semantics to remain equivalent where compatibility was promised.

**Options:**

- Require parity tests, frontend adapter migration, and no remaining callers.
- Require one release cycle with both compatibility and replacement APIs live.
- Allow immediate retirement for endpoints proven unused by tests and code
  search.

**When needed:** Before task 2.12 and before archiving the stabilization change.

## Suggested Answer Order

Answer these first:

1. AshJsonApi migration mount path.
2. Operator console default transport.
3. Packet-run-verification command owner.
4. Packet readiness affordance ownership.
5. `proposed_graph_changes` migration posture.

Then answer these before each implementation track starts:

6. Generated Ash read order.
7. API parity standard.
8. Transport error contract.
9. Durable custom API exceptions.
10. Public generated write posture.
11. Exception burn-down priority.
12. Evidence/run/check ownership.
13. First relationship cluster.
14. First validation consolidation target.
15. Map/json field classification.
16. Frontend routing scope.
17. Query/cache timing.
18. Initial design/component system scope.
19. Frontend test stack.
20. MVP concept promotion decisions.
21. Infrastructure projection visibility.
22. EvidenceCandidate product posture.
23. Stabilization exception threshold.
24. Required gate set.
25. Compatibility retirement evidence.
