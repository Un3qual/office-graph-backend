# Task 6 Report: Cohesion And Test Organization

Status: `DONE_WITH_CONCERNS`

## Delivered

- Moved `OfficeGraph.DurableDelivery.TestWorker` from `lib/` to
  `test/support/office_graph/durable_delivery/test_worker.ex`. A clean production
  compile generated 158 modules and left no TestWorker beam under `_build/prod`;
  its focused test still passes.
- Split `ProposedGraphChange` into one resource module and four independently
  compiled validator/policy modules without changing their public names or Ash
  contracts.
- Replaced five oversized backend test modules with fifteen behavior-domain
  modules. Setup, fixtures, scanners, and query helpers remain single-source in
  five support modules; no large fixture body was copied between test modules.
- Kept all DDL, advisory-lock, and global-state cases serial. No test was changed
  to `async: true`, so no parallelism claim is made.
- Split operator and packet route coverage into reads, commands, and
  errors/security files with one fixture module per route. The original 63 route
  tests remain present within the 146-test frontend suite.
- Split CSS ownership into ordered imports: `shared.css`, `operator.css`, then
  `packets.css`. `global.css` is now the three-line compatibility entrypoint.
  No selector was deleted without caller evidence.
- Replaced the `mark_applied` source-substring assertion with Ash action and
  policy introspection. TypeScript import-boundary enforcement remains AST-based.
  Source scanners that still express architecture ledgers or lock-order shape are
  isolated in the explicitly named `AshBoundaryHeuristicsTest`; they are retained
  heuristics, not runtime proofs.
- Removed the retired `operator_inbox` API ledger row and updated projection,
  direct-Repo, and `authorize?: false` entries to exact current owners/functions.
- Updated `mix architecture.conformance` and current evidence references for the
  new test paths.

## File And Test Shape

- Command loop: 4,707 lines -> 786 packet-contract, 1,758 run-contract, and
  1,751 run-evidence test files plus one 445-line shared fixture macro.
- Concurrency: 3,674 lines -> 531 intake/bootstrap, 266 command-replay, and 680
  evidence test files plus one single-source concurrency support module.
- Ash conformance: 2,756 lines -> 475 API/ledger, 472 resource, and 263 explicitly
  heuristic test files plus one inventory/scanner support module.
- Authorization: 1,828 lines -> 552 scope, 454 typed-flow, and 475 verification
  test files plus one shared fixture module.
- Operator projection: 1,990 lines -> 752 inbox, 400 packet, and 527 run test
  files plus one shared fixture module.
- Frontend route tests: operator 39 and packet 24 tests split across six files;
  fixture payload builders live once in two support files.
- CSS: 820 lines -> 236 shared, 297 operator, 290 packet, and three ordered imports.

## Verification

- Worker/proposed-change focused group: 38 passed.
- Architecture conformance alias after split: 70 passed.
- Full backend suite, seed `982451`: 439 passed.
- Frontend verify: Relay validation passed; TypeScript passed; Biome lint/format
  passed across 97 files; AST import boundaries passed 16 tests; Vitest passed
  146 tests in 26 files; client, SSR, and app-shell production builds passed.
- Production compile: warnings-as-errors passed and TestWorker beam was absent.
- `openspec validate harden-project-quality --strict`: valid.
- Backend format and warnings-as-errors compile: passed.
- Dialyzer/typecheck: `Total errors: 0, Skipped: 0, Unnecessary Skips: 0`.

## Concern Outside Task Ownership

`mix credo --strict` no longer reports any Task 6 support finding after documenting
the deliberate long-quote fixture macros. It remains red on nine near-miss
duplicates in the concurrently changed `lib/office_graph/runs.ex` projection
read helpers: `read_run_required_checks/2` at line 801,
`read_observations/2` at line 822, and `read_evidence_items/2` at line 843,
with Credo reporting nine pairwise near-miss findings (mass 121-169). Those
production changes are owned by another task and were not
refactored here to avoid crossing semantic ownership. The root task must clear
that current branch regression before claiming the canonical static gate green.

## Commits

- `e6fe37f` — isolate test worker and proposed-change modules.
- `e7a909f` — split backend/frontend suites and CSS by behavior ownership.

## Maintainability Review Remediation

- Replaced five helper-injecting `__using__` blocks with minimal case/import/
  alias/attribute macros. Helper implementations now compile once as ordinary
  support-module functions; an AST conformance check rejects future injected
  `def` or `defp` blocks.
- Replaced line-based GraphQL field discovery with Elixir AST traversal. The
  gate now discovers ordinary fields and nested Relay `connection field`
  declarations, including all three previously missed operator connections.
- Promoted the active manual API inventory from an archived change artifact to
  `openspec/specs/backend-model-ownership/api-migration-ledger.md` and recorded
  the three connection fields with owner, reason, replacement, proof, and
  retirement metadata.
- Removed source-string assertions from resource conformance. Ash action and
  exported-function contracts use runtime introspection; the irreducible
  Verification-to-Runs call-shape check is AST-based and explicitly tagged as a
  source-boundary heuristic.
- Review-fix verification: architecture conformance 73 passed; all 12 affected
  split suites 182 passed; strict Credo found no issues; all 96 OpenSpec items
  passed strict validation.
