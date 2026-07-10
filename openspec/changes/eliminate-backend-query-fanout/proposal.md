## Why

Office Graph already bounds the known operator-inbox read path, but backend query efficiency is not yet enforced across other cardinality-sensitive reads and writes. Packet and run creation still execute per-item Ash create actions whose validation changes perform repeated reference lookups, so query count grows linearly with source and required-check counts.

## What Changes

- Add cross-cutting query-efficiency requirements for backend read and write paths whose input or result cardinality can grow.
- Keep operator workflow and generated API relationship reads bounded with query-count scaling coverage.
- Replace per-item packet-source, packet-required-check, and run-required-check creates with Ash-native bulk creates.
- Make shared Ash reference and run-check validation changes batch-aware so bulk actions preserve the existing validation contract without issuing one lookup per record.
- Preserve transactions, authorization posture, action defaults, validation errors, caller-visible record ordering, and public return shapes.
- Add focused query-count tests that compare small and multi-item fixtures instead of depending only on brittle absolute totals.

## Capabilities

### New Capabilities

- `backend-query-efficiency`: Defines bounded query-shape requirements, Ash-native bulk-write behavior, batch-aware validation, and regression coverage for cardinality-sensitive backend paths.

### Modified Capabilities

None.

## Impact

- `OfficeGraph.Repo` Ash write helpers.
- `OfficeGraph.WorkPackets` packet source and required-check creation.
- `OfficeGraph.Runs` run required-check creation.
- `OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences` and `OfficeGraph.Runs.Changes.ValidateRunRequiredCheckContract`.
- Projection and generated GraphQL query-count regression tests.
- No database migration, external dependency, public API, or payload-shape change is expected.
