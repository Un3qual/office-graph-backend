## Context

The archived `reduce-operator-query-load` change already batches the operator inbox projection and protects its main resource reads with Ecto telemetry assertions. The broader backend still lacks a cross-cutting query-shape contract. In particular, `WorkPackets.create_packet/3` creates source references and packet required checks one record at a time, and `Runs.start_run/4` creates run required checks one record at a time. Each create executes Ash changes that query referenced records, so both validation reads and inserts grow per item.

The project requires durable writes to remain Ash-managed unless an explicit architecture exception is justified. These paths also run inside domain transactions and return the created records in input order, so an optimization must preserve action defaults, validation semantics, rollback behavior, and caller-visible shapes.

## Goals / Non-Goals

**Goals:**

- Bound queries for cardinality-sensitive backend reads by relationship/resource type rather than by returned row.
- Batch packet source, packet required-check, and run required-check creation through Ash actions.
- Make the shared reference validators batch-aware so bulk writes do not replace insert N+1 with validation-read N+1.
- Preserve existing authorization, validations, defaults, errors, transactions, record ordering, and public return values.
- Add query-count scaling tests that fail when a future change reintroduces per-row reads or writes.

**Non-Goals:**

- Rewriting all backend commands as bulk actions.
- Removing required reference validation or relying only on database foreign keys.
- Introducing direct `Repo.insert_all`, raw SQL, a new architecture exception, caching, or a database migration.
- Changing GraphQL, JSON API, projection, packet, or run payload semantics.
- Enforcing one exact total query count across unrelated framework or authorization changes.

## Decisions

### Use Ash bulk creates for collection writes

Add a small `OfficeGraph.Repo` helper around `Ash.bulk_create/4` and use it for `WorkPacketSourceReference`, `WorkPacketRequiredCheck`, and `RunRequiredCheck` collections. The helper will request records and errors, stop on the first error, participate in the caller's existing transaction, and normalize failures through the same rollback boundary used by current repo helpers. Inputs will carry pre-generated UUIDs; returned records will be restored to input order by UUID so callers do not depend on database return order.

The bulk call will retain each resource's `:create` action, including set-attribute defaults and custom changes. Empty collections will return an empty list without invoking Ash.

Alternative considered: direct `Repo.insert_all`. It would minimize SQL but bypass Ash actions, require duplicating defaults and validation, and conflict with the model-ownership rule. No exception is justified.

Alternative considered: a separate unchecked internal create action after domain preflight. It would keep the SQL inside Ash but create a second action whose correctness depends on every caller remembering the preflight. Batch-aware validation keeps the invariant on the owning action instead.

### Batch reference validation inside the Ash changes

`ValidateSameScopeReferences.batch_change/3` will collect non-nil reference IDs for all changesets, group them by referenced resource, and read each resource once for the batch. It will then apply the existing scope and graph-item identity checks to every changeset from in-memory lookup maps. `change/3` remains the single-record path and shares the same validation helpers so messages and behavior cannot drift.

`ValidateRunRequiredCheckContract.batch_change/3` will batch-load the referenced runs and packet-required-check rows, index them by run/check/scope, and validate every changeset in memory. It will preserve the existing errors for missing, cross-scope, non-packet-backed, and packet-mismatched checks.

Alternative considered: perform batching only in `WorkPackets` and `Runs`. That would improve the current callers but leave the reusable resource actions prone to N+1 validation whenever another bulk caller is added.

### Test scaling behavior at stable boundaries

Use `OfficeGraph.QueryCounter` to compare one-item and multi-item executions. Assertions will count queries by database source and verify that:

- operator inbox, operator run state, and generated GraphQL relationship reads do not add one query per returned child;
- packet source and required-check validation reads remain bounded per referenced resource within a batch;
- packet source, packet required-check, and run required-check inserts execute in bulk batches rather than one statement per item.

Tests will assert per-source ceilings and deltas instead of one global total. This keeps the tests sensitive to N+1 growth without making them brittle when a legitimate fixed-cost authorization or transaction query is added.

### Keep collection operations transactional and fail closed

Existing packet and run commands already execute within `OfficeGraph.Repo.transaction/1`. Bulk calls will participate in those outer transactions. Any invalid member or bulk error will roll back the whole command; partial packet/run link sets are not allowed. Authorization remains at the command boundary as it is today, and resource actions continue to run with the current internal authorization posture.

## Risks / Trade-offs

- **Risk: custom Ash changes silently fall back to per-record execution** -> Implement and directly test `batch_change/3` query counts for both validators.
- **Risk: bulk-return order differs from input order** -> Pre-generate IDs and explicitly reorder returned records by the input ID list.
- **Risk: bulk errors expose a different shape or allow partial success** -> Stop on error, return errors, normalize through the repo rollback helper, and add invalid-middle-item rollback tests.
- **Risk: query-count tests become coupled to framework internals** -> Assert resource-specific scaling ceilings and deltas, not one absolute request total.
- **Risk: large collections span multiple Ash batches** -> Treat bounded batch growth as acceptable while prohibiting per-item growth; test multiple records within one configured batch and document the batch boundary.

## Migration Plan

1. Add failing query-count and rollback/order regression tests for current packet and run collection writes and unguarded read surfaces.
2. Add batch-aware validation callbacks while preserving single-record behavior.
3. Add the Ash bulk-create repo helper and migrate packet collection writes.
4. Migrate run required-check writes.
5. Run focused tests after each red-green cycle, then run the full backend verification and strict OpenSpec validation.

No data migration or deployment sequencing is required. Rollback is a code revert to the existing per-record Ash create loops; persisted data is schema-compatible in both directions.

## Open Questions

None. The accepted direction is Ash-native bulk creation with batch-aware resource validation.
