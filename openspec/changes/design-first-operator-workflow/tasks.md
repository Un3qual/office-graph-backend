## 1. Scope And Acceptance

- [ ] 1.1 Confirm the first operator workflow starts from manual intake and
  ends at verified completion through existing packet, run, evidence, and
  verification primitives.
- [ ] 1.2 Confirm this change does not add provider webhooks or polling, full
  agent runtime execution, broad React UI polish, full graph canvas, generic
  ordered placement, collaborative rich text, mobile, or workflow-builder
  behavior.
- [ ] 1.3 Confirm GraphQL and JSON API must expose equivalent operator
  workflow state and command outcomes through shared public functions.
- [ ] 1.4 Confirm projection reads are query-backed and authorization-filtered
  rather than persisted as a new workflow aggregate or render cache.

## 2. Projection Contract

- [ ] 2.1 Define an `OfficeGraph.Projections` public API for operator workflow
  inbox rows, item detail, packet readiness, run/evidence state, and
  verification outcome.
- [ ] 2.2 Implement query-backed projection assembly over manual intake
  events, proposed graph changes, graph items, work packets, work runs,
  observations, evidence candidates, evidence items, and verification results.
- [ ] 2.3 Include typed identifiers, graph identities, operation watermarks,
  lifecycle summaries, readiness or blocker reasons, allowed next actions,
  empty states, and stale markers in projection structs or maps.
- [ ] 2.4 Enforce organization, workspace, authorization, sensitivity, and
  tombstone filtering before any projection returns mixed graph or typed
  records.
- [ ] 2.5 Add projection-level tests for pending intake, applied triage,
  not-actionable rows, packet-ready rows, awaiting-evidence runs, verified
  runs, and missing or failed evidence states.

## 3. Operator Commands

- [ ] 3.1 Add shared `OfficeGraph.ApiSupport` functions for reading operator
  workflow projections without local bootstrap behavior leaking into
  production-only paths.
- [ ] 3.2 Reuse existing domain commands for manual intake submission,
  proposed-change application, packet creation, work-run start, observation
  recording, evidence candidate creation or acceptance, and verification
  completion.
- [ ] 3.3 Add or refine command orchestration only where the operator workflow
  needs a stable one-step handoff, while preserving idempotency, operation
  correlation, authorization, audit, and revision boundaries.
- [ ] 3.4 Return structured validation, authorization, idempotency conflict,
  stale-state, not-ready, missing-evidence, failed-check, and lifecycle errors
  with policy-safe details.
- [ ] 3.5 Add tests proving commands reject unauthorized scope crossings,
  duplicate replay conflicts, not-ready packet starts, unrelated evidence, and
  verification without accepted evidence.

## 4. GraphQL And JSON API

- [ ] 4.1 Add GraphQL query types and resolvers for operator inbox, workflow
  item detail, packet readiness, run/evidence state, and verification outcome.
- [ ] 4.2 Add JSON API routes, controller actions, and serializers for the same
  operator workflow projections and commands.
- [ ] 4.3 Ensure GraphQL and JSON call the same public projection and command
  functions and differ only by transport envelope, pagination or filtering
  syntax, and error shape.
- [ ] 4.4 Add API parity tests proving both transports expose equivalent
  business state, allowed next actions, blocker reasons, and error outcomes.
- [ ] 4.5 Document any frontend-facing status vocabulary, empty-state
  semantics, source watermark, and refetch or stale-marker behavior in the
  implementation summary or API tests.

## 5. Verification And Handoff

- [ ] 5.1 Add or update end-to-end tests for
  `manual intake -> inbox triage -> apply proposed changes -> packet handoff
  -> run observation -> evidence acceptance -> verified completion`.
- [ ] 5.2 Run focused tests for projections, operator workflow commands,
  GraphQL/JSON API parity, authorization filtering, idempotency, and
  verification evidence behavior.
- [ ] 5.3 Run the backend verification gate from inside the Nix shell,
  including compile, format, Boundary, architecture conformance, tests, and
  OpenSpec validation.
- [ ] 5.4 Update OpenSpec task checkboxes and add an implementation summary
  mapping each `operator-workflow` requirement to code and tests before
  archiving.
- [ ] 5.5 Commit along the way after projection/API contract work, command
  orchestration, API parity tests, and final verification.

## 6. OpenSpec Validation

- [ ] 6.1 Run `openspec status --change design-first-operator-workflow`.
- [ ] 6.2 Run `openspec validate design-first-operator-workflow --strict`.
- [ ] 6.3 Run `openspec validate --changes --strict`.
- [ ] 6.4 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
