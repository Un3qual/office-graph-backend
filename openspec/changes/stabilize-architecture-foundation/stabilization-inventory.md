# Stabilization Inventory

This inventory captures the current implementation debt before stabilization
refactors begin. It is a point-in-time map, not a target architecture.

## Active OpenSpec Scope

`stabilize-architecture-foundation` is the only active OpenSpec change. It owns
the current API, domain, frontend, and product-concept stabilization work.

## Manual API Surface Inventory

The web API still uses hand-written Absinthe and Phoenix JSON surfaces. These
surfaces are covered in `api-migration-ledger.md` while AshGraphql and
AshJsonApi replacements are introduced.

| Area | Current files | Notes |
| --- | --- | --- |
| GraphQL root schema | `lib/office_graph_web/graphql/schema.ex`, `lib/office_graph_web/graphql/**` | `OfficeGraphWeb.GraphQL.Schema` composes transport-specific query, mutation, type, and error modules by capability. |
| Walking skeleton JSON API | `lib/office_graph_web/json_api/compatibility/controller.ex`, `lib/office_graph_web/json_api/compatibility/serializer.ex` | Manual intake, proposed change application, and verification completion remain custom compatibility surfaces. |
| Packet-run-verification JSON API | `lib/office_graph_web/json_api/packet_run_verification/controller.ex`, `lib/office_graph_web/json_api/packet_run_verification/serializer.ex` | One-shot workflow endpoint remains a compatibility wrapper over broad orchestration. |
| Operator workflow JSON API | `lib/office_graph_web/json_api/operator_workflow/controller.ex`, `lib/office_graph_web/json_api/operator_workflow/serializer.ex` | Operator inbox, item, readiness, run state, and verification outcome are projection endpoints for the current console. |
| Router API scope | `lib/office_graph_web/router.ex` | `/graphql` is mounted manually and JSON routes remain under `/api` until `/api/v1` AshJsonApi migration begins. |

## Generated API Read Inventory

Generated AshGraphql reads now compose into `OfficeGraphWeb.GraphQL.Schema` for
the first safe resource surfaces:

- `OfficeGraph.WorkGraph.Signal` via `listSignals`;
- `OfficeGraph.WorkPackets.WorkPacket` via `listWorkPackets`;
- `OfficeGraph.Runs.Run` via `listWorkRuns`.

Generated AshJsonApi reads mount under `/api/v1` through
`OfficeGraphWeb.JsonApi.Router`:

- `GET /api/v1/signals`;
- `GET /api/v1/work-packets`;
- `GET /api/v1/work-runs`.

The legacy `/api` routes remain compatibility and migration surfaces only.
Generated lifecycle writes are not mounted.

## Domain And Database Exception Inventory

Direct database mutation and transaction exceptions are already tracked in the
durable backend architecture exception ledger. Current high-risk owners are
WorkGraph, Integrations, Identity, Tenancy, Authorization, ProposedChanges,
Content, `OfficeGraph.ApiSupport`, WorkPackets, Runs, Verification, and the
WorkGraph evidence-candidate validation change.

`OfficeGraph.ApiSupport` remains a compatibility facade for manual transport
surfaces. Packet-run-verification parsing and local owner bootstrap now delegate
to `OfficeGraph.PacketRunVerification`, which owns the composite workflow
transaction, flow digest replay guard, step-key namespace, and sequencing across
packet preparation, run start, observation recording, evidence suggestion,
evidence acceptance, and summary reads. Later stabilization work should keep
burning down direct transaction and authorization-bypass entries inside the
owning domains while keeping transport code to context loading plus error
mapping.

## WorkGraph Relationship Inventory

WorkGraph resources now define internal Ash relationships for the first safe
raw UUID references. The initial relationship pass covers graph item links,
document references, parent WorkGraph records, evidence candidate/evidence item
links, verification result links, and operation correlation references. These
relationships are intentionally not public so generated API reads do not expose
new infrastructure-shaped relationship fields by default.

Cross-domain references from WorkGraph evidence records into Runs,
WorkPackets, and Identity remain raw UUIDs for now. They are deferred to the
domain cleanup tasks that resolve evidence acceptance ownership and remove
dependency-cycle risks.

## WorkPackets Relationship And Contract Inventory

WorkPackets resources now define internal Ash relationships for the first safe
raw UUID references. The pass covers packet operation/current-version/version
links, version packet/operation/source/check links, source-reference graph-item
links, and required-check verification-check links. These relationships remain
non-public so generated API reads do not expose new infrastructure-shaped
relationship fields by default.

WorkPackets create and update actions now own more of the packet contract:
packet create no longer accepts `current_version_id` or caller-selected state
and derives draft state, source-reference create derives the fixed graph-item
source fields, required-check create derives the fixed required/pending fields,
version create derives `draft`/`ready` lifecycle state from packet readiness
inputs, and current-version updates validate that the selected version belongs
to the packet and target scope while syncing packet state from that version.
Idempotent replay, operation locking, and the packet creation transaction
remain in the narrow command layer.

## Runs Relationship And Contract Inventory

Runs resources now define internal Ash relationships for their safe raw UUID
references. The pass covers run packet/version/operation/initiator links, run
required-check and observation children, run events, required-check run/check
links, observation run/operation/check/graph-item links, and run-event run
links. These relationships remain non-public so generated API reads do not
expose new infrastructure-shaped relationship fields by default.

Runs create actions now own stable run contract fields: run create derives the
initial lifecycle fields, required-check create derives pending state,
observation create derives ingestion time, and run-event create remains a
private append action. Run create now owns packet/version ownership, packet
readiness, and authority-envelope validation; observation create now owns
run/check/graph reference validation. `OfficeGraph.Runs` no longer
pre-validates those same invariants before calling private Ash actions. Command
code still owns persisted packet-version reload, operation locking,
transaction boundaries, replay/idempotency comparisons, selected required-check
copying, and run lifecycle mutation. Accepted evidence outcomes now enter Runs
through one narrow `apply_accepted_verification_result/2` hook owned by the
Verification acceptance path; generic public helpers for satisfying required
checks or forcing run verification state have been retired.

## WorkGraph Command Organization

`OfficeGraph.WorkGraph` is now a thin public facade. Internal reads live in
`OfficeGraph.WorkGraph.Queries`, proposal-application graph writes live in
`OfficeGraph.WorkGraph.ProposalCommands`, verification lifecycle writes live in
`OfficeGraph.WorkGraph.VerificationCommands`, and shared transaction/Ash helper
behavior lives in `OfficeGraph.WorkGraph.CommandSupport`.

The split preserves the current public `OfficeGraph.WorkGraph` function surface
so existing API, projection, proposal, packet-run, and test callers do not
churn while the internals are prepared for the validation cleanup tasks.

## WorkGraph Validation Ownership

Proposal command modules now reload persisted parents only to create stable
graph relationships. They no longer pre-validate parent scope or open-state
before child creates. Those invariants are owned by the Ash create actions
through `ValidateSameScopeReferences`, `ReviewFinding.ValidateOpenTask`, and
`VerificationCheck.ValidateOpenReviewFinding`.

Verification completion still owns its transaction-scoped lifecycle
recomputation and parent lock ordering in `VerificationCommands`; evidence
acceptance owns its pass/fail rule in `OfficeGraph.Verification` and delegates
only run lifecycle mutation to the narrow Runs hook when accepted evidence is
run-backed.

## Map Field Classification

`map-field-classification.md` classifies every current Ash `:map` attribute so
flexible storage fields remain intentional. `RunEvent.payload` is internal run
event trace data, `ProposedGraphChange.payload` is temporary legacy
raw/suggestion/compatibility input, and `EvidenceItem.visibility_constraints`
is a visibility-policy envelope until policy rules need typed fields or
resources. Similar metadata maps remain allowed only for provenance, replay,
trace, raw import, or content-rendering details; product-queryable domain data
must move to typed fields, child resources, or typed command inputs.

## Domain Cleanup Ledger Burn-Down

The domain cleanup pass narrowed the Runs exception ledger instead of leaving
the original broad accepted-evidence helpers in place. `OfficeGraph.Runs` now
approves one accepted-result lifecycle hook,
`apply_accepted_verification_result/2`, instead of public helpers for marking
required checks satisfied or forcing run verification state. The Verification
ledger now records that Verification owns the accepted evidence pass/fail rule
and delegates only run lifecycle mutation to Runs.

## Broad Authorization Bypass Inventory

Many internal Ash reads and writes currently use `authorize?: false`. The
durable exception ledger now tracks those bypasses by owner and function so new
or broadened bypasses fail architecture conformance unless they are documented.

The largest groups are:

- bootstrap and policy setup in Identity, Tenancy, and Authorization;
- trace writes in Operations, Audit, and Revisions;
- projection reads in `OfficeGraph.Projections`;
- cross-context validation changes in WorkGraph and Runs;
- packet, run, evidence, and verification workflow internals.

## Frontend Architecture Gap Inventory

The React app exists under `assets/src`, but the original package manager and
tooling files were at the project root. Stabilization moves package metadata,
Vite, TypeScript, Vitest setup, and the lockfile under `assets` and switches
verification to pnpm.

Current frontend gaps:

- route and package tooling were split between project root and `assets`;
- the operator app shell hardcodes `/assets/operator/main.css` and
  `/assets/operator/main.js`;
- frontend verification was not wired into project verification;
- `OperatorConsole.tsx` still combines route state, data calls, layout, and
  panels;
- product frontend data still uses temporary JSON adapters instead of the
  locked GraphQL product API direction.

The first frontend guardrail checks that package metadata lives under
`assets/package.json`, pnpm is the package manager, Vite can emit the hardcoded
app-shell asset paths, and frontend scripts run from the project Nix shell.
