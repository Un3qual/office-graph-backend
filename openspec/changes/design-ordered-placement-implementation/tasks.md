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

## 2. Storage And Boundary Planning

- [ ] 2.1 Select the first product surface that justifies generic
  graph-addressable placement tables instead of typed placement tables.
- [ ] 2.2 Define the ordered placement bounded-context public API and its
  allowed callers from typed domains, projections, jobs, and change proposals.
- [ ] 2.3 Draft typed migration shapes for ordered collections, placements,
  placement versions, task-list placement compatibility, and rich text block
  placement compatibility.
- [ ] 2.4 Define concrete uniqueness indexes for active membership and active
  position keys, including root-safe parent scope handling.
- [ ] 2.5 Define lifecycle states for collections, placements, placement
  versions, degraded collections, repair markers, and restored placements.

## 3. Position Keys And Commands

- [ ] 3.1 Implement and test a fixed-alphabet bytewise sortable fractional
  position-key library.
- [ ] 3.2 Define insert, move, delete, restore, rebalance, repair, and backfill
  command contracts with idempotency, operation context, authorization, and
  reason fields.
- [ ] 3.3 Implement sibling-bound key generation for insert between, prepend,
  append, and empty collection cases.
- [ ] 3.4 Implement optimistic collection and placement version conflict
  handling, including retry-only-when-unambiguous behavior.
- [ ] 3.5 Define command behavior for nested placements, parent changes, cycle
  prevention, lifecycle conflicts, and cross-scope rejection.

## 4. Rebalance And Repair

- [ ] 4.1 Define rebalance thresholds for key length, minimum gap, and
  concentrated inserts.
- [ ] 4.2 Implement rebalance as a placement operation that creates placement
  versions under one operation correlation record.
- [ ] 4.3 Define repair detectors for duplicate active keys, missing current
  versions, orphaned parents, and broken denormalized current fields.
- [ ] 4.4 Implement deterministic repair only when reconstruction is provable;
  otherwise mark the collection degraded and require administrator or support
  intervention.

## 5. Projections And Realtime

- [ ] 5.1 Define ordered projection query contracts that compute visible dense
  ordinals after authorization, scope, lifecycle, sensitivity, and tombstone
  filtering.
- [ ] 5.2 Define placement-aware pagination cursors and stale/refetch behavior
  for ordered projections.
- [ ] 5.3 Define invalidation and rebuild contracts for any persisted ordered
  read model or ordinal cache.
- [ ] 5.4 Define realtime ordering event payloads as projection hints with
  placement identity, collection identity, operation identity, and source
  watermark.

## 6. Traceability And Migration

- [ ] 6.1 Link placement commands to operation correlation, typed revision
  records, domain events, realtime invalidation, and change proposal results.
- [ ] 6.2 Define audit and authorization decision triggers for sensitive
  placement operations, repair, cross-scope moves, external writes, approvals,
  and sensitive agent actions.
- [ ] 6.3 Backfill placement versions and operation records for existing v1
  domain-owned ordering without presenting backfill as user-authored history.
- [ ] 6.4 Verify historical order reconstruction for task-list ordering, rich
  text block ordering, rebalance, repair, restore, and content-plus-move
  operations.

## 7. Validation

- [x] 7.1 Run `openspec status --change design-ordered-placement-implementation`.
- [x] 7.2 Run `openspec validate design-ordered-placement-implementation --strict`.
- [x] 7.3 Run `openspec validate --changes --strict` after coordinating with
  other active OpenSpec edits.
- [x] 7.4 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
