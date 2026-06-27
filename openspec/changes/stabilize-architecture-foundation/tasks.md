## 1. Baseline And Guardrails

- [ ] 1.1 Re-run OpenSpec discovery and confirm no other active change owns API,
  domain, frontend, or concept stabilization scope.
- [ ] 1.2 Add or update a stabilization inventory documenting current manual
  GraphQL fields, Phoenix JSON routes, serializers, `OfficeGraph.ApiSupport`
  commands, direct database exceptions, broad `authorize?: false` paths, and
  frontend architecture gaps.
- [ ] 1.3 Add an API migration ledger entry for each existing manual
  GraphQL/JSON surface that remains live, including owner, reason, replacement
  target, safety/parity tests, and deletion or retirement condition.
- [ ] 1.4 Add architecture conformance coverage that fails when new manual API
  resource surfaces are added without ledger coverage.
- [ ] 1.5 Add architecture conformance coverage that fails when new direct
  database mutation paths, raw SQL paths, or broad authorization bypasses are
  added without exception-ledger coverage.
- [ ] 1.6 Fix or document frontend verification prerequisites so the project uses
  local dependencies and does not accidentally run a system TypeScript compiler.
- [ ] 1.7 Move JavaScript package/tooling files under `assets`, switch frontend
  dependency management from npm/package-lock to pnpm, and update scripts to run
  from the project Nix shell.
- [ ] 1.8 Add app-shell verification proving `/operator` references built asset
  paths that the frontend build can produce.
- [ ] 1.9 Run baseline verification:
  `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate stabilize-architecture-foundation --strict`,
  `nix --extra-experimental-features 'nix-command flakes' develop --command mix architecture.conformance`,
  frontend verification, and focused API/frontend tests.

## 2. API Surface Stabilization

- [ ] 2.1 Split `OfficeGraphWeb.Schema` into root schema composition plus focused
  `OfficeGraphWeb.GraphQL.*` modules organized transport first, capability
  second, and purpose third, without route or behavior changes.
- [ ] 2.2 Move JSON API controllers and serializers into focused
  `OfficeGraphWeb.JsonApi.*` modules organized transport first, capability
  second, and purpose third, without route or behavior changes.
- [ ] 2.3 Keep GraphQL and JSON API transport-specific `common` helpers
  separate; do not create a generic `OfficeGraphWeb.Api` dumping ground for
  errors, params, serializers, or resolver behavior.
- [ ] 2.4 Extract transport-specific error mapping so JSON API controllers and
  GraphQL resolvers do not duplicate stable error codes and safe details while
  still presenting transport-appropriate envelopes.
- [ ] 2.5 Keep existing GraphQL/JSON parity tests green while modularizing the
  transport modules and error presentation.
- [ ] 2.6 Identify the first safe AshGraphql/AshJsonApi read-only resource
  surfaces for WorkGraph, WorkPackets, and Runs.
- [ ] 2.7 Mount or compose generated AshGraphql reads for the selected resources
  without exposing private lifecycle creates or updates.
- [ ] 2.8 Mount AshJsonApi for the selected resource reads under `/api/v1`,
  keeping existing `/api` migration endpoints live only while desired callers
  still need them.
- [ ] 2.9 Add generated API tests proving actor scope, capability checks,
  structured errors, and behavior parity with current migration reads where
  safety requires parity.
- [ ] 2.10 Split packet-run-verification orchestration out of
  `OfficeGraph.ApiSupport` into smaller Ash-shaped domain commands for packet
  preparation, run start, observation recording, evidence
  suggestion/acceptance, and verification recomputation.
- [ ] 2.11 Keep any one-shot GraphQL or JSON packet-run-verification entrypoint
  as temporary compatibility/workflow orchestration over those durable commands,
  with transport code limited to context loading and error mapping.
- [ ] 2.12 Add deletion or retirement tasks for manual endpoints that have
  generated or command/projection replacements.

## 3. Ash And Domain Cleanup

- [ ] 3.1 Add modeled Ash relationships to the first WorkGraph resources that
  currently carry only raw UUID references, starting with graph item, signal,
  task, review finding, verification check, artifact, evidence item, evidence
  candidate, and verification result.
- [ ] 3.2 Split `OfficeGraph.WorkGraph` into focused command/query modules while
  preserving its public boundary and current behavior.
- [ ] 3.3 Move duplicated WorkGraph open-state, same-scope, graph-item, and
  lifecycle validation into one Ash action/change location per invariant.
- [ ] 3.4 Add relationships and richer action contracts for WorkPackets packet,
  version, source reference, and required-check resources.
- [ ] 3.5 Refactor packet creation/readiness so stable resource invariants live
  in Ash actions/changes and replay/idempotency remains in a narrow command
  layer.
- [ ] 3.6 Add relationships and richer action contracts for Runs run,
  run-required-check, execution-observation, and run-event resources.
- [ ] 3.7 Consolidate duplicated run/check/observation validation so wrappers and
  Ash changes do not own the same invariant twice.
- [ ] 3.8 Resolve evidence acceptance ownership between WorkGraph, Runs, and
  Verification, then keep evidence acceptance, verification result recording,
  required-check satisfaction, and run-state recomputation behind one command
  path.
- [ ] 3.9 Classify `RunEvent.payload`, `ProposedGraphChange.payload`,
  `EvidenceItem.visibility_constraints`, and similar map fields as raw/debug
  metadata, temporary compatibility payload, or product-queryable data that must
  be promoted.
- [ ] 3.10 Burn down at least one architecture exception ledger entry per domain
  cleanup stage or explicitly narrow the entry and update its retirement
  condition.

## 4. Frontend Architecture Foundation

- [ ] 4.1 Promote the existing concept tokens into a shared token source usable
  from CSS and TypeScript.
- [ ] 4.2 Confirm the frontend foundation stack with a small spike covering pnpm
  under `assets`, StyleX/Vite, one React Aria primitive, one TanStack Query
  projection hook against GraphQL, and verification through the Nix shell.
- [ ] 4.3 Add shared UI primitives for badge, button, panel, pane header, nav
  rail, text field, and empty/error state without embedding operator-workflow
  domain mapping logic.
- [ ] 4.4 Refactor `OperatorConsole.tsx` into route/container state, projection
  hooks, workbench layout, inbox list, selected item detail, packet readiness
  panel, run state panel, and verification panel modules.
- [ ] 4.5 Move operator-specific status-to-tone and action-label mapping into the
  operator-workflow feature boundary.
- [ ] 4.6 Introduce a GraphQL projection-client interface for operator workflow
  data that returns frontend view models independent of GraphQL response shape
  and future socket/live invalidation payloads.
- [ ] 4.7 Keep any existing JSON adapter only as a documented temporary bridge
  during migration, or replace it with GraphQL immediately if the required
  GraphQL projection exists.
- [ ] 4.8 Remove frontend-derived packet readiness command assembly from the
  render path or isolate it behind a documented temporary adapter until the
  backend projection provides explicit command affordances.
- [ ] 4.9 Add URL-selected inbox row behavior only if needed for the current
  operator route; defer broader React routing until a second real product route
  is accepted.
- [ ] 4.10 Add frontend tests for loading, empty, error, selection, readiness,
  run, verification, and app-shell asset behavior.
- [ ] 4.11 Run frontend verification through the project Nix shell and confirm it
  uses pnpm under `assets` without depending on global Node, npm, or TypeScript
  installs.

## 5. Product Concept Simplification

- [ ] 5.1 Add a canonical vocabulary note or spec summary mapping user-facing
  concepts to backend infrastructure concepts.
- [ ] 5.2 Update API and UI planning docs so Signal, Work Item, Work Packet,
  Run, Check, Evidence, and Verification are the default MVP product spine,
  with Change Proposal used only when proposed mutation review is a real
  workflow.
- [ ] 5.3 Stop introducing `proposed_graph_change`, `GraphPatch`, execution
  package, agent-ready block, operation correlation, evidence candidate, and
  verification result as default operator-facing product nouns.
- [ ] 5.4 Decide whether the Change Proposal / `proposed_graph_changes` safety
  object remains in current MVP scope, narrows to a future agent-generated
  mutation workflow, or is deleted/deferred until that workflow is real.
- [ ] 5.5 Update operator projections so infrastructure records appear as trace,
  audit, or debug details rather than primary user-facing nouns.
- [ ] 5.6 Model evidence candidate behavior in API/UI projections as Evidence
  with explicit state unless a later workflow requires a dedicated evidence
  review concept; do not expose EvidenceCandidate as a default product noun.
- [ ] 5.7 Add proposal checklist guidance requiring workflow justification before
  promoting planned concepts such as questions, decisions, rich text quotes,
  SCIM group mapping, explicit grants, agent executions, graph conversations,
  or provider-specific review objects into user-facing MVP scope.

## 6. Final Verification And Handoff

- [ ] 6.1 Run `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate stabilize-architecture-foundation --strict`.
- [ ] 6.2 Run `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --specs --strict`.
- [ ] 6.3 Run backend architecture conformance and focused API tests affected by
  the stabilization work.
- [ ] 6.4 Run frontend verification through pnpm under `assets` and the app-shell
  asset test.
- [ ] 6.5 Run `git diff --check`.
- [ ] 6.6 Update the change artifacts with implementation notes, remaining
  exception-ledger entries, and follow-up sequencing before archive.
