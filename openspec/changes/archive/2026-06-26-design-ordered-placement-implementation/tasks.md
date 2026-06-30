## 1. Review And Acceptance

- [x] 1.1 Confirm this change remains design-only and does not add Phoenix,
  Ash, Ecto, migration, API, frontend, Oban, realtime, or agent-runtime code.
- [x] 1.2 Confirm ordered placement is scoped collection membership, not an
  authorization container or generic graph mutation bypass.
- [x] 1.3 Confirm reusable graph-addressable placement and typed
  domain-owned placement both preserve concrete foreign keys.
- [x] 1.4 Confirm dense ordinals are derived read values and not durable write
  inputs.
- [x] 1.5 Confirm strategy-specific storage remains deferred until concrete
  product semantics are accepted.

## 2. Deferral Decision

- [x] 2.1 Confirm no first product surface currently justifies generic
  graph-addressable placement tables instead of typed placement tables.
- [x] 2.2 Confirm task-list ordering, rich text block ordering, shared placement
  tables, position-key libraries, rebalance/repair behavior, ordered
  projections, realtime ordering events, and ordering migrations remain
  deferred to later accepted OpenSpec changes.
- [x] 2.3 Confirm this change records future guardrails only and does not make
  ordered placement the next active planning or implementation lane.
- [x] 2.4 Confirm any future generic ordered placement work must first identify
  a concrete product surface, storage owner, bounded-context API, migration
  shape, index strategy, lifecycle model, projection contract, and traceability
  requirements in a new or reactivated change.

## 3. Validation

- [x] 3.1 Run `openspec status --change design-ordered-placement-implementation`.
- [x] 3.2 Run `openspec validate design-ordered-placement-implementation --strict`.
- [x] 3.3 Run `openspec validate --changes --strict` after coordinating with
  other active OpenSpec edits.
- [x] 3.4 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
