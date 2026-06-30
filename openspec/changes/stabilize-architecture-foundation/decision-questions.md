# Architecture Stabilization Decisions And Open Questions

This worksheet captures the current answers for
`stabilize-architecture-foundation` and keeps the remaining discussion points
short enough to use during planning.

## Locked Direction

These are now accepted unless a later OpenSpec change reopens them.

- GraphQL and JSON API code stay under `OfficeGraphWeb`, but they use separate
  folders and module namespaces:
  `OfficeGraphWeb.GraphQL.*` / `lib/office_graph_web/graphql/` and
  `OfficeGraphWeb.JsonApi.*` / `lib/office_graph_web/json_api/`.
- API code is organized transport first, capability second, purpose third.
- Transport-specific helpers stay under that transport's `common` namespace.
  Domain behavior, command ownership, and projections live under
  `OfficeGraph.*`, not `OfficeGraphWeb`.
- Generated AshJsonApi mounts under `/api/v1`.
- The Office Graph product frontend uses GraphQL as its normal API. REST/JSON
  API exists for customer integrations. Socket/live transport is internal-only
  when realtime workflow needs it.
- Any current frontend dependency on Phoenix JSON endpoints is migration debt,
  not the desired architecture.
- Packet readiness command affordances belong in backend projections. The
  frontend should not infer packet/run command input from raw graph links.
- Generated Ash reads should be the default for resource-shaped data. The work
  should be mostly automatic or mechanical once resources have the right Ash
  API declarations, policies, relationships, and read actions.
- Generated writes are not part of the current stabilization work. Writes that
  drive lifecycle, audit, verification, or cross-resource mutations stay behind
  explicit domain commands unless a later spec opens a specific action.
- The current packet-run-verification one-shot flow is transitional. Durable
  API commands should be split into smaller Ash-shaped command actions owned by
  the real domains: packet preparation, run start, observation recording,
  evidence suggestion/acceptance, and verification recomputation. Any one-shot
  packet-run-verification surface remains temporary compatibility/workflow
  orchestration with a deletion path.
- All direct Ecto, raw SQL, broad `authorize?: false`, manual transaction, raw
  UUID relationship, and duplicated-validation debt is in scope to burn down.
  The work should still be sequenced so each stage stays reviewable.
- All raw UUID relationships should eventually become Ash relationships where
  they represent domain links.
- All stable domain invariants should eventually move into Ash actions,
  changes, validations, or public domain commands instead of being duplicated
  in wrappers and transports.
- Map/JSON fields must be classified. Anything that drives filters,
  authorization, operator decisions, reports, or stable API fields should become
  typed/queryable product data. Trace/debug/import payloads can stay flexible.
- The query/cache layer should probably arrive with websocket/live integration
  or the first real multi-view server-state pressure. TanStack Query is the
  leading candidate, but the exact adoption point should follow the realtime
  work.
- The frontend foundation should start from TanStack, StyleX, and React Aria,
  pending a small compatibility spike.
- JavaScript tooling should move under `./assets`: `package.json`, lockfile,
  Vite config, TypeScript config, Vitest setup, and related frontend scripts.
  Switch from npm/package-lock to pnpm.
- Planned product concepts are allowed to be considered MVP scope, but default
  operator projections should still use a small product spine and hide
  infrastructure records behind trace/debug/audit fields unless the operator
  has a real action to take.
- Approach 2 is accepted for Change Proposal, proposed graph changes, map/json
  proposal payloads, and evidence candidate simplification:
  `ProposedGraphChange` / generic graph patch semantics are removed or deferred
  from the current MVP. Future proposal functionality must model typed proposed
  domain commands, not mutations to the graph projection.
- The graph remains a read/projection surface. Domain commands mutate canonical
  resources; graph projections reflect those mutations afterward.
- Manual intake should create a Signal, draft Work Item, or triage record
  through normal domain actions unless a real proposal approval/rejection
  workflow exists.
- Evidence is the product concept. Suggested, accepted, rejected, stale, and
  missing evidence are states of Evidence in API/UI projections. Any durable
  evidence-candidate storage is internal/transitional and must not become the
  default product noun.
- Verification owns evidence acceptance, check satisfaction, verification
  result recording, and recomputation rules. Runs owns run lifecycle state and
  receives updates through explicit commands.
- `product-vocabulary.md` is the local checklist for API/UI naming during this
  change. New user-facing concepts must justify the workflow, operator action,
  projection contract, authorization behavior, and why the canonical product
  spine is insufficient.
- During stabilization, breaking changes are allowed. The product is not near
  release, so backwards compatibility must not preserve bad internal contracts.
- Compatibility ledgers are drift-control tools, not promises to keep old APIs.
  They should explain what exists, why it exists, and what deletes or replaces
  it.

## Discussion Still Needed

### 7. What "API parity" means if backwards compatibility does not matter

"Parity" does not mean exact response envelopes or old field names forever.
Since breaking changes are allowed, replacement APIs only need behavioral
parity where safety matters.

Replacement is about these old surfaces:

- manual Absinthe root fields and resolvers;
- Phoenix JSON controllers and serializers;
- `OfficeGraph.ApiSupport` command/projection helpers;
- frontend fetch code that depends on those manual shapes.

They are replaced by:

- generated AshGraphql reads for internal product/frontend resource reads;
- generated AshJsonApi reads under `/api/v1` for customer integration surfaces;
- narrow custom domain command/projection APIs for workflows that are not simple
  resource reads;
- GraphQL projection clients in the React frontend.

Parity should prove:

- same authorization/scope behavior;
- same durable state changes for replacement commands;
- same idempotency/replay behavior where applicable;
- equivalent validation failures and safe structured error codes;
- equivalent policy-filtered projection meaning.

It does not need to preserve old JSON field names, old GraphQL field names, or
dual-run compatibility once we decide no caller should remain on the old path.

### 8. Structured error contract

This can stay simple.

Domain commands should return stable, safe domain errors with a code, message,
field/path when relevant, and metadata safe for the caller.

Each transport maps those errors into its normal envelope:

- GraphQL: GraphQL errors with `extensions.code`, optional field/path details,
  and safe metadata.
- JSON API: HTTP status plus a JSON error object with the same stable code and
  safe details.
- Socket/live internal transport later: event-level failure with the same code
  vocabulary.

Decision still needed: define the first code vocabulary. Good starting set:
`unauthorized`, `forbidden`, `not_found`, `validation_failed`,
`conflict`, `idempotency_conflict`, `stale_state`, `unsupported_action`,
`rate_limited`, and `internal_error`.

### 16. Routing before a second product route

This is about how much frontend routing structure to add before the product has
more than `/operator`.

Recommendation:

- Keep Phoenix route `/operator` as the only product route for now.
- Inside React, keep local selection state unless sharing/deep-linking selected
  inbox items is immediately useful.
- If deep linking is useful, add URL-selected row state with query/search params
  for the operator route.
- Do not add fake nav destinations or route scaffolding for product surfaces
  that do not exist.
- Add a router package only when a second real product route is accepted.

Decision still needed: do we need deep links to selected operator inbox rows
now, or can selection stay local until the second route?

### 18. Frontend stack details

Your proposed stack is reasonable, with some constraints:

- TanStack Query is a good fit for server state, especially once websocket/live
  updates become invalidation/refetch signals.
- TanStack Router is optional. It is useful once multiple real routes exist,
  but not needed for a single `/operator` screen.
- StyleX is a reasonable styling/token option if we commit to its compile-time
  setup under Vite and keep component APIs generic.
- React Aria is a strong accessibility base for interactions where native HTML
  is not enough, but use it where it pays for itself rather than wrapping every
  simple element.
- React local state is enough for local selection, expanded panels, tabs, and
  transient form controls. Avoid a global client store until there is real
  cross-route client-only workflow state.

Decision still needed: run a small frontend foundation spike before broad UI
refactor:

- pnpm under `assets`;
- Vite builds with StyleX;
- one React Aria primitive;
- one TanStack Query projection hook against GraphQL;
- verification command works inside the Nix shell.

### 24. Required gates

The gate set should distinguish quick local checks from heavier CI checks.

Recommended local gates for most stabilization changes:

- OpenSpec validation for the active change;
- `git diff --check`;
- focused backend/API tests for touched areas;
- frontend verification when frontend files change.

Recommended full CI gates:

- OpenSpec validation for active changes and durable specs;
- architecture conformance;
- full backend test suite or accepted project equivalent;
- frontend typecheck, tests, build, and app-shell asset check;
- API replacement/parity tests for any changed API surface.

Decision still needed: exact command names after the first guardrail batch adds
or fixes them. The current planning target is `mix architecture.conformance`
plus `pnpm --dir assets verify`, but the implementation batch must make those
commands real and reliable.

## Full Question Register

1. AshJsonApi path: answered. Use `/api/v1`.
2. Operator console transport: answered. Use GraphQL. REST is for customer
   integrations. Socket/live is internal when needed.
3. Packet-run-verification owner: answered. Split the one-shot flow into
   smaller Ash-shaped domain commands; keep any one-shot surface temporary and
   delete it after clients move to durable commands.
4. Packet readiness affordance: answered. Backend projection owns it.
5. `proposed_graph_changes` rename/concept: answered. Remove/defer generic
   `ProposedGraphChange` / graph patch semantics from current MVP. Future
   ChangeProposal work proposes typed domain commands, not graph projection
   mutations.
6. Generated Ash reads: answered directionally. Most resource-shaped reads
   should be generated/mechanical once Ash declarations are correct.
7. API parity: explained above. Safety/behavior parity matters; old response
   shapes do not unless we deliberately keep them.
8. Structured errors: open. Need first stable code vocabulary.
9. Manual custom endpoint exceptions: answered. Nothing in current work should
   need durable custom resource endpoints unless it is a command/projection
   that Ash generation cannot express.
10. Generated writes: answered. Not in current stabilization scope.
11. Exception burn-down: answered. Do all categories, sequenced by risk.
12. Evidence acceptance/recomputation: answered. Verification owns evidence
   acceptance, check satisfaction, verification result recording, and
   recomputation rules; Runs owns run lifecycle state.
13. Raw UUID relationships: answered. All real domain links should become Ash
   relationships over time.
14. Validations into Ash actions: answered. All stable invariants should move.
15. Map/JSON promotion: answered. Promote all queryable product data; generic
   proposal payloads can exist only as raw/suggestion/compatibility input, not
   durable queryable product state.
16. Routing: open. Decide whether selected inbox row state needs a URL now.
17. Query/cache: answered directionally. Likely with realtime/websocket work,
   probably using TanStack Query.
18. Component/design stack: partially answered. Start with TanStack, StyleX,
   React Aria, and confirm with a spike.
19. Frontend tooling location: answered. Move JS tooling under `assets` and use
   pnpm.
20. Planned MVP concepts: answered broadly. They can be considered, but should
   still require workflow justification before becoming first-screen UI/API
   nouns.
21. Infrastructure projection visibility: answered. Keep infrastructure behind
   trace/debug/audit fields by default.
22. EvidenceCandidate: answered. Project as Evidence states by default; any
   separate evidence-candidate storage is internal/transitional unless a later
   accepted workflow needs a dedicated review queue.
23. Stabilization allowance: answered. Breaking changes are allowed; do not
   preserve bad contracts for compatibility.
24. Gates: open. Need exact local/CI command set after guardrails exist.
25. Compatibility retirement evidence: answered. Backwards compatibility does
   not matter; prove no desired caller remains and delete/replace the bad path.
