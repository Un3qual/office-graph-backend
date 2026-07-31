## Why

Office Graph currently runs its project-boundary linting through bespoke Mix
aliases in addition to Credo. The checks should use the standard static-analysis
surface so contributors receive one consistent linter workflow without losing
the repository-wide coverage required for tracked SQL, planning paths, or stale
inventory entries.

## What Changes

- Add one project-local, repository-wide Credo check for planning and database
  boundaries.
- Preserve the existing syntax-aware scanner, debt comparison, exact
  fingerprints, and non-mutating behavior behind the Credo check.
- Report source violations, parallel planning files, stale debt, and malformed
  inventory entries as normal Credo issues at actionable paths.
- **BREAKING** Remove the `office_graph.planning_boundaries` and
  `office_graph.database_boundaries` Mix aliases after Credo parity is proven.
- Make canonical verification run these boundaries exactly once through
  `mix credo --strict`, with a focused `--only` invocation available for local
  diagnosis.
- Add behavior tests for Credo success and each boundary-failure class without
  changing the existing debt or approved-exception inventories.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-quality-gates`: Require planning and database-boundary enforcement
  to use the canonical static-analysis linter surface rather than separate
  project-specific verification commands.

## Impact

- Affects `.credo.exs`, project-local Credo check code, `mix.exs`, and focused
  project-quality tests.
- Does not change product behavior, production dependencies, scanner
  fingerprints, inventory contents, API contracts, or persisted data.
