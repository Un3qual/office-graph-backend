## 1. Scope And Acceptance

- [x] 1.1 Confirm the first operator workflow starts from manual intake and
  ends at verified completion through existing packet, run, evidence, and
  verification primitives.
- [x] 1.2 Confirm this change does not add provider webhooks or polling, full
  agent runtime execution, broad React UI polish, full graph canvas, generic
  ordered placement, collaborative rich text, mobile, or workflow-builder
  behavior.
- [x] 1.3 Confirm GraphQL and JSON API must expose equivalent operator
  workflow state and command outcomes through shared public functions.
- [x] 1.4 Confirm projection reads are query-backed and authorization-filtered
  rather than persisted as a new workflow aggregate or render cache.

## 2. Projection Contract

- [x] 2.1 Define an `OfficeGraph.Projections` public API for operator workflow
  inbox rows, item detail, packet readiness, run/evidence state, and
  verification outcome.
- [x] 2.2 Implement query-backed projection assembly over manual intake
  events, proposed graph changes, graph items, work packets, work runs,
  observations, evidence candidates, evidence items, and verification results.
- [x] 2.3 Include typed identifiers, graph identities, operation watermarks,
  lifecycle summaries, readiness or blocker reasons, allowed next actions,
  empty states, and stale markers in projection structs or maps.
- [x] 2.4 Enforce organization, workspace, authorization, sensitivity, and
  tombstone filtering before any projection returns mixed graph or typed
  records.
- [x] 2.5 Add projection-level tests for pending intake, applied triage,
  not-actionable rows, packet-ready rows, awaiting-evidence runs, verified
  runs, and missing or failed evidence states.

## 3. Operator Commands

- [x] 3.1 Add shared `OfficeGraph.ApiSupport` functions for reading operator
  workflow projections without local bootstrap behavior leaking into
  production-only paths.
- [x] 3.2 Reuse existing domain commands for manual intake submission,
  proposed-change application, packet creation, work-run start, observation
  recording, evidence candidate creation or acceptance, and verification
  completion.
- [x] 3.3 Add or refine command orchestration only where the operator workflow
  needs a stable one-step handoff, while preserving idempotency, operation
  correlation, authorization, audit, and revision boundaries.
- [x] 3.4 Return structured validation, authorization, idempotency conflict,
  stale-state, not-ready, missing-evidence, failed-check, and lifecycle errors
  with policy-safe details.
- [x] 3.5 Add tests proving commands reject unauthorized scope crossings,
  duplicate replay conflicts, not-ready packet starts, unrelated evidence, and
  verification without accepted evidence.

## 4. GraphQL And JSON API

- [x] 4.1 Add GraphQL query types and resolvers for operator inbox, workflow
  item detail, packet readiness, run/evidence state, and verification outcome.
- [x] 4.2 Add JSON API routes, controller actions, and serializers for the same
  operator workflow projections and commands.
- [x] 4.3 Ensure GraphQL and JSON call the same public projection and command
  functions and differ only by transport envelope, pagination or filtering
  syntax, and error shape.
- [x] 4.4 Add API parity tests proving both transports expose equivalent
  business state, allowed next actions, blocker reasons, and error outcomes.
- [x] 4.5 Document any frontend-facing status vocabulary, empty-state
  semantics, source watermark, and refetch or stale-marker behavior in the
  implementation summary or API tests.

## 5. Verification And Handoff

- [x] 5.1 Add or update end-to-end tests for
  `manual intake -> inbox triage -> apply proposed changes -> packet handoff
  -> run observation -> evidence acceptance -> verified completion`.
- [x] 5.2 Run focused tests for projections, operator workflow commands,
  GraphQL/JSON API parity, authorization filtering, idempotency, and
  verification evidence behavior.
- [x] 5.3 Run the backend verification gate from inside the Nix shell,
  including compile, format, Boundary, architecture conformance, tests, and
  OpenSpec validation.
- [x] 5.4 Update OpenSpec task checkboxes and add an implementation summary
  mapping each `operator-workflow` requirement to code and tests before
  archiving.
- [x] 5.5 Commit along the way after projection/API contract work, command
  orchestration, API parity tests, and final verification.

## 6. OpenSpec Validation

- [x] 6.1 Run `openspec status --change design-first-operator-workflow`.
- [x] 6.2 Run `openspec validate design-first-operator-workflow --strict`.
- [x] 6.3 Run `openspec validate --changes --strict`.
- [x] 6.4 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
