## Why

The project-local database-boundary scanner recognizes `Ecto.Multi` writes but
omits its public read operations. Repository-authored code can therefore query
the database through a multi without the canonical Ash persistence gate
classifying the direct Ecto access.

## What Changes

- Classify `Ecto.Multi.all`, `Ecto.Multi.one`, and `Ecto.Multi.exists?` as
  direct Ecto access through fully qualified and explicitly aliased receivers.
- Preserve receiver-aware behavior so unrelated modules with the same function
  names are not classified.
- Add focused scanner regressions for all three read operations and the
  unrelated-receiver case.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-quality-gates`: Extend database-boundary scanning to query
  operations composed through `Ecto.Multi`.

## Impact

The change affects only the project-local Credo database-boundary scanner, its
focused tests, and the canonical quality-gate specification. It introduces no
runtime API, dependency, database, or migration changes.
