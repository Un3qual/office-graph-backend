## Context

Office Graph has a backend walking skeleton for manual intake, proposed graph
changes, work packets, work runs, evidence, and verification. Those primitives
are durable but still exposed as step-oriented APIs rather than one coherent
operator workflow. The next product slice should let an operator move from a
messy manual signal to verified completion while preserving the company-wide
work graph direction and avoiding deferred platform work.

Current constraints:

- OpenSpec remains the source of truth for scope.
- Backend commands run through Phoenix API, Ash, Boundary, Postgres, GraphQL,
  JSON API, operation correlation, revision, audit, and authorization
  boundaries.
- Manual intake is the first adapter. Provider webhooks and polling remain
  deferred.
- The React product UI is expected, but this change should define stable
  projection and command contracts before committing to frontend app structure.
- Generic ordering, broad rich text/editor behavior, full graph canvas, and
  full agent runtime remain out of scope.

## Goals / Non-Goals

**Goals:**

- Define a first operator workflow from manual intake through verified
  completion.
- Define the projection contracts needed for an inbox, triage/readiness view,
  work packet view, run/evidence view, and verification outcome.
- Reuse existing domain commands for intake, proposed-change application,
  packet creation, work-run start, observation recording, evidence acceptance,
  and verification.
- Make GraphQL and JSON API expose equivalent workflow state and errors.
- Keep reads authorization-filtered and typed so the UI does not infer product
  semantics from raw database rows.

**Non-Goals:**

- No provider webhook, API polling, Sentry, GitHub, Slack, Figma, email, or
  spreadsheet integration implementation.
- No full React frontend, visual design system, mobile app, or broad workflow
  builder in this change.
- No full agent runtime, autonomous code-editing surface, or unrestricted tool
  execution.
- No full graph canvas, generic ordered placement, or persisted projection
  cache.
- No replacement of the existing walking-skeleton command path with a new
  workflow engine.

## Decisions

### 1. Treat the first operator workflow as a projection plus narrow commands

The operator workflow should be a product contract over existing primitives,
not a new persistence owner. A new projection boundary should assemble typed
state from manual intake events, proposed changes, graph items, work packets,
runs, observations, evidence candidates, evidence items, and verification
results. Mutations should continue to call owning domain commands.

Alternatives considered:

- **Create a new workflow aggregate:** Easier to render but risks duplicating
  truth already owned by graph, packet, run, and verification domains.
- **Expose raw tables and let the UI compose:** Faster initially but leaks
  business semantics and authorization decisions into the client.

### 2. Use query-backed projections first

The first projection should be query-backed and rebuildable from durable
records. It may expose stable row identifiers, typed references, lifecycle
summaries, reason codes, and source operation watermarks, but it should not
introduce render caches or rollup tables until volume or UX latency proves the
need.

Alternatives considered:

- **Persist inbox and workflow state immediately:** Useful later, but premature
  before the shape of the operator loop is dogfooded.
- **Realtime-first delivery:** Useful for active runs, but the first contract
  can use refetch and explicit stale markers.

### 3. Make the first workflow human/operator-run first

The first workflow should support an operator preparing and verifying work with
manual or human-run observations. It should preserve autonomy posture fields
and agent-ready classifications, but it should not require internal agents to
execute work before the product loop is usable.

Alternatives considered:

- **Build internal agent execution first:** Attractive for the long-term
  product, but it expands tool permissions, runtime isolation, approvals, and
  audit behavior before the operator surface is stable.
- **Stay manual-intake-only:** Too narrow; it does not prove work packet,
  evidence, and verification value.

### 4. Keep GraphQL and JSON API equivalent

GraphQL and JSON API should expose the same operator workflow projection and
commands. The transports may differ in envelope, pagination syntax, or error
shape, but they must call the same public context functions and return the
same business states.

Alternatives considered:

- **GraphQL-only first:** Faster for a frontend, but violates the accepted API
  direction.
- **JSON-only first:** Simple for smoke tests, but leaves the GraphQL contract
  behind before product UI work starts.

### 5. Defer UI implementation until contracts are stable

This change should be implementation-ready for backend projection/API work.
If frontend work starts from it, the first React surface should be a thin
operator console over these contracts, not a marketing page or full graph
editor. A separate frontend change may own project scaffolding, styling,
browser verification, and UI ergonomics once the backend contract is accepted.

Alternatives considered:

- **Create React app in this change:** Produces a visible artifact sooner but
  risks locking UI structure before projection semantics are stable.
- **Never describe UI surfaces here:** Leaves the backend without a product
  target and encourages generic API accretion.

## Risks / Trade-offs

- [Risk] The workflow projection becomes a second source of truth. ->
  Mitigation: keep it query-backed, typed, and derived from owning domains.
- [Risk] The first surface is too backend-shaped for operators. -> Mitigation:
  require empty states, next actions, blocker reasons, and concise status
  summaries in the projection contract.
- [Risk] Agent-runtime fields imply automation that is not implemented. ->
  Mitigation: expose autonomy posture and agent-readiness as readiness
  classifications while keeping execution human/operator-run first.
- [Risk] API parity slows iteration. -> Mitigation: share public context
  functions and serializers so GraphQL and JSON differ only by transport.
- [Risk] Deferred UI work loses product pressure. -> Mitigation: define the
  concrete operator surfaces now and make frontend implementation a natural
  follow-up, not an undefined future.

## Migration Plan

This change should not require destructive migrations. Later implementation
may add read helpers, projection modules, API types, controllers, serializers,
and tests over existing tables. If a small additive column or index is needed
to expose a stable projection watermark or state, it must be justified by the
implementation change and remain backward-compatible.

Rollback should leave existing walking-skeleton commands and records intact.
Projection endpoints can be removed or hidden without deleting manual intake,
packet, run, evidence, or verification data.

## Open Questions

- Should the first implementation include only backend projection/API work, or
  should it also scaffold a minimal React operator console?
- Which status vocabulary is the best first UI-facing vocabulary for operator
  rows: lifecycle states only, readiness states only, or a small derived
  workflow status?
- Should the first operator inbox include only manual intake events, or also
  existing packet/run verification items that were created through direct API
  calls?
