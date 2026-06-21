## 1. App Baseline

- [x] 1.1 Generate the Phoenix API application at the repository root with
  `OfficeGraph` / `OfficeGraphWeb`, Ecto/Postgres enabled, and LiveView, HTML
  views, and frontend assets disabled.
- [x] 1.2 Add only the backend dependencies needed for the walking skeleton:
  Phoenix API, Ecto/Postgres, Ash, Boundary, Absinthe GraphQL, JSON API
  support, test helpers, and supporting verification tooling.
- [x] 1.3 Configure application, repo, endpoint, runtime/test/dev database,
  logger, formatter, and Mix aliases from inside the project Nix shell.
- [x] 1.4 Add Docker Compose configuration for local development/test Postgres
  with a named service, stable local connection settings, health check,
  durable named volume, and documented start/stop/reset commands.
- [x] 1.5 Add documented setup and verification commands that use
  `nix --extra-experimental-features 'nix-command flakes' develop --command`.
- [x] 1.6 Verify the clean app baseline with compile, format check, and the
  default test suite before adding domain behavior.
- [x] 1.7 Commit the generated app baseline before starting domain/resource
  implementation.

## 2. Boundary And Context Layout

- [x] 2.1 Add Boundary configuration and define the initial public/private
  module rules for `OfficeGraph` and `OfficeGraphWeb`.
- [x] 2.2 Create public context modules needed by the walking skeleton:
  identity, tenancy, authorization, operations, audit, revisions, work
  containers, work graph, content, integrations/intake, software proving,
  proposed changes, verification, runs, work packets, and API-facing support.
- [x] 2.3 Place internal implementation modules under their owning context and
  avoid cross-context imports of private modules.
- [x] 2.4 Add the Boundary verification command to Mix aliases or release gate
  documentation.
- [x] 2.5 Add a minimal Boundary test or command check that fails on private
  cross-context imports.

## 3. Identity, Tenancy, And Bootstrap

- [x] 3.1 Create migrations/resources for organizations, workspaces,
  initiatives, optional workstreams, principals, principal profiles, sessions
  or session references, capabilities, roles, role capabilities, role
  assignments, policy bundle/version anchors, and credential metadata.
- [x] 3.2 Implement local/test bootstrap for first organization, workspace,
  initiative, owner principal/profile, initial role assignment, capabilities,
  policy anchor, and owner session context.
- [x] 3.3 Implement thin authenticated principal/session context structs and
  public verification helpers for API entrypoints and domain actions.
- [x] 3.4 Implement the first authorization check path for walking-skeleton
  reads, writes, proposed-change application, evidence linking, and verified
  completion.
- [x] 3.5 Add tests proving bootstrap is idempotent in dev/test and that
  unauthorized principals cannot read or mutate skeleton records.

## 4. Persistence And Resource Skeleton

- [x] 4.1 Create migrations/resources for operation correlation records and the
  minimal typed revision, authorization decision, audit, and tombstone records
  needed by walking-skeleton actions.
- [x] 4.2 Create migrations/resources for graph items and typed graph
  relationships with concrete references and atomic graph identity plus typed
  resource creation.
- [x] 4.3 Create migrations/resources for raw archives, external sources,
  external references, normalized intake events, source identity,
  replay/idempotency identity, and duplicate-handling outcome.
- [x] 4.4 Create migrations/resources for signals, tasks, review findings,
  verification checks, evidence items, artifacts, and verification results.
- [x] 4.5 Create skeletal migrations/resources for work packets, runs, run
  events, and proposed graph changes only to the extent needed for readiness,
  traceability, proposed mutation safety, and verification.
- [x] 4.6 Create the narrowed rich text v1 tables/resources for documents,
  current blocks, basic marks/references, whole-document semantic revisions,
  and derived plain text used by skeleton body fields.
- [x] 4.7 Add migration/resource tests for foreign keys, unique constraints,
  soft-delete-aware uniqueness where needed, graph identity atomicity, and
  raw archive/idempotency behavior.

## 5. Walking Skeleton Domain Actions

- [x] 5.1 Implement public domain action for manual intake submission that
  stores the raw archive, normalized event, source/replay identity, operation
  correlation, and duplicate-handling outcome.
- [x] 5.2 Implement proposed graph change creation, validation, authorization,
  rejection, and application paths for skeleton resources and relationships.
- [x] 5.3 Implement domain actions for creating and linking the manual intake
  signal, task, review finding, required verification check, evidence item,
  artifact when needed, and verification result.
- [x] 5.4 Implement type-specific lifecycle transitions through verified
  completion without using one universal graph status enum.
- [x] 5.5 Ensure every state-changing action receives authenticated
  principal/session context, tenant/scope context, and operation correlation
  context before authorization and mutation.
- [x] 5.6 Add tests for successful loop progression, invalid proposed changes,
  unauthorized proposed changes, duplicate intake replay, and audit/revision
  traceability.

## 6. GraphQL And JSON API Surface

- [x] 6.1 Add minimal GraphQL schema, context loading, queries, and mutations
  for bootstrap/test auth context, manual intake, proposed change review and
  application, graph/loop reads, evidence linking, and verified completion.
- [x] 6.2 Add minimal JSON API routes/controllers or Ash JSON API resources for
  the same walking-skeleton operations.
- [x] 6.3 Ensure GraphQL and JSON API entrypoints call the same public domain
  actions and do not duplicate lifecycle, authorization, or mutation logic.
- [x] 6.4 Implement authorization-filtered reads and structured validation,
  authorization, idempotency, conflict, and lifecycle error responses for both
  API surfaces.
- [x] 6.5 Add API smoke tests proving GraphQL and JSON API produce equivalent
  durable state and equivalent denial/conflict outcomes.

## 7. Verification Gates

- [x] 7.1 Add or update project verification aliases/scripts for compile,
  format check, tests, Boundary verification, database setup/migration checks,
  and OpenSpec validation.
- [x] 7.2 Add an end-to-end test for
  `manual intake signal -> task -> review finding -> required verification
  check -> evidence item -> verified completion`.
- [x] 7.3 Add focused tests for authorization filtering/redaction,
  operation-correlation linkage, typed revision linkage, audit record creation,
  and proposed-change safety.
- [x] 7.4 Run the full backend verification gate from inside the Nix shell and
  fix failures.
- [x] 7.5 Run `openspec validate first-backend-walking-skeleton --strict`.
- [x] 7.6 Run `openspec validate --changes --strict`.

## 8. Handoff And Scope Guard

- [x] 8.1 Update OpenSpec task checkboxes as implementation tasks complete and
  keep unrelated future tracks open.
- [x] 8.2 Document Docker Compose Postgres startup/reset commands,
  network-backed Hex dependency setup, and repeatable development commands
  discovered during implementation.
- [x] 8.3 Confirm no React frontend, LiveView UI, provider webhook/API polling,
  full agent runtime, generic ordered-placement framework, or full rich text
  editor behavior was introduced in this change.
- [x] 8.4 Commit along the way at app baseline, persistence/resources, domain
  loop, API surface, and final verification checkpoints.
- [x] 8.5 Prepare a review summary mapping implemented code back to each
  `first-backend-walking-skeleton` spec capability before applying or
  archiving the change.
