## Why

The repository's apparent full verification gate omits most behavioral tests, while the project-wide audit found several current correctness, transport-parity, operator-safety, and maintainability defects that existing static checks do not detect. These gaps should be repaired before more features are stacked on the current command-loop work.

## What Changes

- Make one canonical, non-mutating verification gate cover strict OpenSpec validation, dependency advisories, backend static analysis and the complete ExUnit suite, and frontend generation, type-checking, tests, and production builds.
- Isolate local verification state across worktrees and add tracked CI that runs the canonical Nix-based gate.
- Correct run-state reduction, evidence result-slot conflicts, policy-decision auditing, unsafe migration rollback, and boolean runtime configuration.
- Give operator projections policy-safe summaries and complete command option bundles; bound growing collections; and remove the retired inbox surface.
- Unify command input parsing and safe error classification across GraphQL and JSON, including concurrency conflicts and nested reasons.
- Make command-form errors field-specific and accessible, make Relay requests cancellable, and remove stale UI code, dependencies, styles, unsafe casts, and internal product jargon.
- Move test-only code out of production, replace generated durable-spec purpose placeholders, and split the clearest oversized test/support boundaries without changing product behavior.
- Record larger contract gaps found by the audit that require separate compatibility and migration designs rather than silently expanding this remediation.

## Capabilities

### New Capabilities

- `project-quality-gates`: Defines the canonical repository verification, isolation, advisory, CI, and durable-spec hygiene contract.

### Modified Capabilities

None. The product fixes restore behavior already required by the canonical specifications.

## Impact

The change affects Mix aliases and local verification scripts, Nix-backed CI, run and verification command services, authorization-decision persistence, operator GraphQL/JSON surfaces, Relay projections and forms, frontend dependencies and styles, selected tests/support modules, migrations, and canonical OpenSpec descriptions. Public command envelopes remain backward compatible; retired unreleased query fields may be removed under the project's unreleased-development policy.
