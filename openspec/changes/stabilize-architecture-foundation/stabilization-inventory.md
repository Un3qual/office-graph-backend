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
