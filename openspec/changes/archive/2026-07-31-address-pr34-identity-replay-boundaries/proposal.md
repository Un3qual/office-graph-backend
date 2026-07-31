## Why

The current enterprise-directory implementation can leave a directory-created
principal active after its last accepted directory basis ends and can report a
changed directory-binding replay as successful without applying the requested
state. The database-boundary gate also omits direct repository rollback control,
leaving a straightforward bypass of the Ash persistence policy.

## What Changes

- Base principal deactivation on durable principal provenance and all accepted
  active directory identity bases, not the origin label of the last processed
  directory link.
- Make directory-binding operation replay compare the full material binding
  contract and reject incompatible reuse of the same operation identity.
- Classify `OfficeGraph.Repo.rollback` and explicit repository aliases as direct
  Ecto transaction control while ignoring unrelated receivers.
- Add behavioral regressions for shared-principal deprovisioning, changed
  binding replays, and receiver-aware rollback scanning.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `enterprise-directory-sync`: Clarify last-basis principal deactivation and
  complete-contract directory-binding replay behavior.
- `project-quality-gates`: Extend receiver-aware database-boundary scanning to
  explicit repository rollback control.

## Impact

The change affects enterprise directory binding and identity reconciliation,
the project-local Credo database-boundary scanner, and their focused test
suites. It introduces no external API or dependency changes.
