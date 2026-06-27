# Architecture Stabilization Decision Questions

This is the short decision worksheet for `stabilize-architecture-foundation`.
It keeps all open questions in one place, with just enough context to answer
them without rereading the full design.

## Locked Decisions

These are already decided:

- GraphQL and JSON API code stay under `OfficeGraphWeb`.
- GraphQL and JSON API use separate module/file namespaces:
  `OfficeGraphWeb.GraphQL.*` / `lib/office_graph_web/graphql/` and
  `OfficeGraphWeb.JsonApi.*` / `lib/office_graph_web/json_api/`.
- API code is organized transport first, capability second, purpose third.
- Transport-specific shared helpers live under that transport's `common`
  namespace.
- Domain behavior, command ownership, and projections live under
  `OfficeGraph.*`, not `OfficeGraphWeb`.
- The first implementation batch is guardrails and inventories, not broad
  refactors.

## Answer First

These decisions block the larger API/domain/frontend cleanup.

### 1. Where should generated AshJsonApi live during migration?

Pick the mount path for strict/generated JSON API routes while the current
manual `/api` endpoints stay live.

Options:

- `/api`: direct, but mixes manual compatibility endpoints with generated
  resource contracts.
- `/api/v1`: clear version boundary, but implies broader versioning decisions.
- `/jsonapi`: clean temporary migration lane, but probably not the final public
  path.

Also answer: if `/jsonapi` is temporary, what event promotes it to the durable
path?

### 2. Which transport should the operator console dogfood first?

Pick the default frontend adapter while the projection-client boundary is being
introduced.

Options:

- Keep JSON first: least churn because the current UI already uses JSON.
- Move to GraphQL when generated reads exist: dogfoods the future API earlier.
- Support both only for parity tests: useful, but do not turn this into UI
  complexity unless needed.

Also answer: if JSON stays first, what is the switch condition?

### 3. Who owns packet-run-verification orchestration?

Pick the domain command boundary that replaces the orchestration currently in
`OfficeGraph.ApiSupport`.

Options:

- `OfficeGraph.WorkPackets`: packet readiness focused, but may overreach into
  runs and verification.
- `OfficeGraph.Runs`: execution focused, but packet creation and verification
  can feel secondary.
- `OfficeGraph.Verification`: evidence/check focused, but the workflow starts
  before verification.
- New `OfficeGraph.WorkExecution`: clean cross-domain workflow owner, but adds
  a new context.
- `OfficeGraph.OperatorWorkflow`: product-facing, but risky if a UI/projection
  boundary owns lifecycle.

Also answer: allowed dependencies, transaction boundary, idempotency key,
authorization contract, and projection read contract.

### 4. Should packet readiness become a backend-projected command affordance?

Decide whether the backend should provide packet readiness actions/input shape,
or whether the frontend may temporarily assemble readiness input.

Options:

- Backend projects readiness now: cleaner and stops frontend domain inference.
- Temporary frontend adapter: faster UI cleanup, but requires explicit
  retirement criteria.
- Block readiness UI cleanup until backend projection support exists.

Also answer: if temporary, what exact backend projection replaces it?

### 5. How aggressive should the `proposed_graph_changes` rename be?

The product term should be "Change Proposal." Decide how far to push the rename
now.

Options:

- Rename code and storage now: cleanest language, widest migration.
- Translate API/UI now, storage later: protects user-facing language with less
  blast radius.
- Keep old term for now: lowest churn, but lets retired vocabulary spread.

Also answer: do GraphQL fields, JSON fields, frontend types, or fixtures need
compatibility aliases?

## API Surface Questions

### 6. Which generated Ash reads come first?

Choose the first resources to expose through AshGraphql/AshJsonApi reads. Good
candidates are low-risk read-only resources, resources already using Ash API
extensions, or resources needed by the operator projection.

### 7. What does API parity mean during migration?

Define what replacement APIs must preserve. Authorization, operation context,
idempotency, durable state changes, and safe error codes should be equivalent.
Response envelopes and field names may be transport-native unless compatibility
requires exact shape.

### 8. What is the structured error contract per transport?

Decide what is shared semantically and what is transport-specific. Likely
shape: domain commands return stable domain errors; GraphQL and JSON API map
those into their own envelopes with shared codes and safe details.

### 9. Which manual endpoints are durable custom exceptions?

Identify which manual GraphQL fields, JSON routes, serializers, and projections
remain custom instead of being replaced by generated Ash APIs.

Valid custom reasons include cross-domain commands, policy-filtered mixed
projections, integrations/webhooks, or temporary compatibility. Everything
else should have a replacement or retirement target.

### 10. Are any generated writes safe to expose soon?

Decide whether stabilization allows generated creates/updates at all.

Conservative default: generated reads only; lifecycle-driving writes stay
behind domain commands until a spec explicitly makes an action public.

## Domain And Ash Questions

### 11. Which exception ledger entries burn down first?

Prioritize the first debt class to retire or narrow:

- transport-owned orchestration;
- broad `authorize?: false`;
- direct Ecto writes;
- raw SQL;
- manual transaction boundaries.

The first target should reduce real drift without breaking current smoke value.

### 12. Who owns evidence acceptance and run/check recomputation?

Decide whether this is owned by the same command boundary as
packet-run-verification, by Verification, by Runs, or by one facade command over
multiple internal owners.

This controls evidence acceptance, verification result recording,
required-check satisfaction, and run-state recomputation.

### 13. Which raw UUID references become Ash relationships first?

Pick the first relationship cluster. Candidates:

- WorkGraph resources that feed operator projections;
- WorkPackets resources needed by packet readiness;
- Runs/Verification resources that drive execution state.

### 14. Which validation group moves into Ash actions first?

Pick the first invariant group to consolidate:

- WorkGraph open-state/same-scope checks;
- graph-item checks;
- packet readiness;
- required-check validation;
- run/check state transitions;
- evidence acceptance.

### 15. Which map/json fields must become queryable product data?

Classify fields such as `RunEvent.payload`, `ProposedGraphChange.payload`, and
`EvidenceItem.visibility_constraints`.

Use this rule: if a field drives filters, authorization, operator decisions,
reports, or stable API fields, promote it. If it is trace/debug/import data, it
can stay flexible.

## Frontend Questions

### 16. How much routing should exist before a second real product route?

Options:

- keep only `/operator` and local selection state;
- add URL-selected inbox row behavior;
- add a minimal React router with only implemented routes;
- add nav scaffolding with unavailable affordances.

Avoid fake product routes unless there is an accepted product decision behind
them.

### 17. When should a query/cache layer be introduced?

Options:

- defer until a second route or realtime invalidation exists;
- add lightweight feature-local hooks now;
- add a full query/cache library during frontend foundation work.

The goal is to stop scattered fetch logic without overbuilding the first UI
cleanup.

### 18. What is the minimum design/component system scope?

Confirm the first shared UI scope. Current planned minimum:

- tokens usable from CSS and TypeScript;
- badge;
- button;
- panel;
- pane header;
- nav rail;
- text field;
- empty/error state.

Also decide whether table/list, tabs, modal, tooltip, and form-field primitives
belong in the first batch or should wait.

### 19. Which frontend verification command is authoritative?

Pick the local/CI frontend check shape. It must use project-local dependencies,
avoid the system TypeScript compiler, build the app, and verify Phoenix app
shell asset references.

Options:

- one fixed `npm run verify`;
- separate typecheck/test/build/app-shell commands;
- a Mix task that runs frontend verification through the Nix shell.

## Product Concept Questions

### 20. Which planned concepts are MVP-facing now?

The default MVP spine is Signal, Change Proposal, Work Item, Work Packet, Run,
Check, Evidence, and Verification.

Explicitly accept or defer these before they appear in API/UI contracts:

- Questions;
- Decisions;
- rich text quote snapshots;
- SCIM group mapping;
- explicit grants;
- agent executions;
- graph conversations;
- provider-specific review objects;
- EvidenceCandidate as a separate product concept;
- OperationCorrelation as visible operator vocabulary.

### 21. How should infrastructure details appear in operator projections?

Decide what belongs in the default operator view versus trace/debug/audit
fields.

Default posture: product-spine fields in normal UI; infrastructure records such
as GraphItem, GraphRelationship, OperationCorrelation, RawArchive,
ExecutionObservation, VerificationResult, PolicyBundle, audit records, and
revisions stay behind trace/debug/audit surfaces.

### 22. Should EvidenceCandidate remain internal?

Options:

- show candidates as Evidence with states such as suggested, accepted,
  rejected, stale, or missing;
- keep EvidenceCandidate entirely internal and show only accepted Evidence;
- promote EvidenceCandidate as a separate review queue concept.

The simpler default is Evidence with state unless operators need a dedicated
candidate-review workflow.

## Governance Questions

### 23. What is allowed during stabilization without opening a new exception?

Define the threshold for narrow bug fixes, manual API edits, small UI fixes,
and domain changes.

Suggested posture: behavior-preserving fixes are fine; new public routes,
fields, screens, direct DB paths, or auth bypasses need OpenSpec or ledger
coverage.

### 24. Which checks are required gates locally and in CI?

Pick the authoritative gate set. Current candidates:

- OpenSpec validation;
- `mix architecture.conformance`;
- focused API tests;
- frontend verification;
- app-shell asset test;
- `git diff --check`.

Also decide which are quick local gates versus full CI gates.

### 25. What evidence retires a compatibility endpoint?

Define what must be true before a manual GraphQL/JSON compatibility endpoint is
removed, redirected, or demoted.

Possible retirement evidence:

- replacement parity tests pass;
- frontend adapter has migrated;
- no remaining callers;
- authorization and structured errors are preserved;
- optionally, both old and new APIs ran together for one release cycle.

## Suggested Answer Order

Answer these before implementation beyond guardrails:

1. AshJsonApi path.
2. Operator console default transport.
3. Packet-run-verification command owner.
4. Packet readiness affordance ownership.
5. `proposed_graph_changes` migration posture.

Then answer the rest as their implementation track starts:

- API surface: questions 6-10.
- Domain/Ash: questions 11-15.
- Frontend: questions 16-19.
- Product concepts: questions 20-22.
- Governance: questions 23-25.
