## Context

The archived quality-boundary change added a syntax-aware database scanner, a
planning-path scanner, inventory comparison, and two Mix aliases invoked before
Credo in canonical verification. The scanners are repository linters rather
than product runtime behavior, but their separate command surface duplicates
the static-analysis workflow contributors already use.

The project pins Credo 1.7.19. Its `Credo.Check` API supports a
`run_on_all_source_files/3` callback and accepts issues for arbitrary paths.
That is enough to present repository-wide diagnostics through Credo. Credo's
normal source loader is not enough to implement the policy by itself: it does
not parse tracked `.sql` files, and a per-file check cannot discover deleted
occurrences that remain in an inventory.

## Goals / Non-Goals

**Goals:**

- Make `mix credo --strict` the canonical reporting and enforcement surface for
  planning and database-boundary linting.
- Preserve Git-tracked scope, stable fingerprints, exact inventory comparison,
  SQL-file coverage, and non-mutating behavior.
- Report every boundary diagnostic as a normal Credo issue at an actionable
  source or inventory path.
- Remove redundant project-specific Mix aliases after behavior parity is
  proven.
- Keep Credo-specific and scanner code out of production runtime modules.

**Non-Goals:**

- Reclassify, regenerate, approve, or remove any database-access inventory
  entry.
- Replace syntax-aware scanning with text matching or Credo's configured source
  list.
- Publish a reusable Credo package or add a new dependency.
- Change product code, APIs, database schemas, or canonical policy.

## Decisions

### 1. Use one project-local all-source Credo check

`OfficeGraph.Credo.Check.ProjectBoundaries` will use `Credo.Check` with
`run_on_all: true` and implement `run_on_all_source_files/3`. It will run the
planning and database-boundary engines once for Credo's working directory and
append their results to Credo's issue store.

The check will be loaded through `.credo.exs` `requires` and enabled as an
extra check. Credo remains a development/test dependency; no Credo module will
be compiled into the production application.

Alternative considered: implement a full `Credo.Plugin` that injects an
execution task. Rejected because the normal custom-check API already supports
repository-wide execution and issue reporting; a plugin would add pipeline
coupling without additional required behavior.

### 2. Retain a scanner engine behind the linter interface

The database scanner will continue to enumerate Git-tracked sources and parse
eligible Elixir syntax itself. It will continue to scan migrations, seeds, and
tracked SQL files even when those paths are absent from Credo's configured
Elixir source list. The gate will continue to compare that scan with the debt
and approved-exception inventories.

The planning scanner, database scanner, and inventory gate will move from
production `lib/office_graph/project_quality/**` into a build-only
`credo_checks/office_graph/project_boundaries/**` area. They remain independent
of Credo so their classification and inventory behavior can be tested directly.

Alternative considered: rewrite classification as ordinary per-file Credo
checks. Rejected because it would omit tracked SQL files, make stale detection
impossible, and couple fingerprints to Credo's source selection.

### 3. Map repository diagnostics to actionable Credo issues

The Credo check will translate diagnostics as follows:

- new and changed database occurrences attach to the source path and reported
  line;
- stale debt attaches to the debt inventory and names the former source
  locator;
- malformed approved or debt entries attach to the owning inventory;
- parallel planning diagnostics attach to the prohibited path.

All issue messages will retain the diagnostic kind, construct or path, and
fingerprint information needed to correct the violation. The check will not
rewrite source or inventory files.

### 4. Run the boundary once through canonical static analysis

After parity coverage passes, canonical `verify` will stop invoking
`office_graph.planning_boundaries` and `office_graph.database_boundaries`.
The existing `credo --strict` step will run the combined boundary check once.

Contributors can run only this check with:

`mix credo --strict --only OfficeGraph.Credo.Check.ProjectBoundaries`

The check is intentionally repository-wide even when Credo receives a narrowed
file list, because stale inventories and tracked non-Elixir sources are global
repository properties.

## Risks / Trade-offs

- **A repository-wide Credo check may surprise callers linting one file.** →
  Document the global behavior in the check explanation and provide the
  focused `--only` command as the supported diagnostic workflow.
- **Credo may change extension APIs in a future upgrade.** → Pin the behavior to
  the locked Credo version and cover check registration, execution, issue
  mapping, and exit behavior with tests.
- **Moving scanner modules could accidentally change fingerprints.** → Preserve
  classifier inputs and fingerprint algorithms exactly, then prove the current
  896-entry debt baseline remains accepted without inventory edits.
- **A Credo wrapper could hide duplicate scans.** → Remove both bespoke aliases
  and assert canonical verification contains only the Credo execution path.

## Migration Plan

1. Add failing tests for project-wide Credo issue mapping and registration.
2. Move the scanner engines to the build-only Credo-check area without changing
   their behavior.
3. Add and configure the all-source Credo check.
4. Prove the current repository baseline passes the focused Credo invocation
   and representative violations fail with actionable issues.
5. Remove the two Mix aliases and their command-wrapper tests.
6. Run strict OpenSpec validation and the complete canonical verification gate,
   confirming inventories and the worktree remain unchanged.

Rollback is a normal revert that restores the two Mix aliases and their verify
entries. Inventory contents and fingerprints do not require migration.

## Open Questions

None.
