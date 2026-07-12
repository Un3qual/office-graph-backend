## Context

OfficeGraph already enforces strict formatting, Credo, Boundary, duplicate-code, architecture-smell, Dialyzer, backend-test, frontend-test, Relay, typecheck, and production-build gates. The audit found gaps around that strong baseline: `mix verify` does not run strict OpenSpec or advisory checks, its frontend Relay step recompiles an already compiled backend, the GraphQL query/schema modules form a compile cycle, and verification command ownership is concentrated in a 1,039-line module even though waiver execution is an independent transactional workflow. A dated 554-line review handoff also remains in the root after every finding in it was resolved.

## Goals / Non-Goals

**Goals:**

- Make the named full-project gate complete, reproducible, and free of redundant backend compilation.
- Clear the current Postgrex advisory with the smallest compatible lockfile update.
- Extract the verification-waiver workflow behind the existing `OfficeGraph.Verification` public boundary.
- Remove stale audit material that is neither current guidance nor an OpenSpec artifact.

**Non-Goals:**

- Change product behavior, APIs, persistence, or UI output.
- Split files solely to satisfy an arbitrary line limit.
- Introduce a generic command framework or speculative abstractions for future verification commands.
- Upgrade unrelated dependencies.

## Decisions

### Keep one public verification boundary and extract one owned workflow

`OfficeGraph.Verification` remains the caller-facing context. The waiver transaction moves to `OfficeGraph.Verification.Waiver`, while a small internal command-support module owns the existing scope, locking, tracing, and transaction-normalization primitives shared by waiver and evidence commands. This lowers the responsibility count of the context entrypoint without creating a public framework or changing call sites.

The alternative was to split every verification operation at once. That would create a large review surface and force abstractions before the command boundaries have proved stable. Leaving the entire file untouched was also rejected because the waiver path has its own authorization, replay, locking, state-validation, persistence, and trace lifecycle.

### Let callers declare that the backend is already compiled

The Relay schema script keeps standalone safety by compiling by default. The Mix-owned frontend gate sets an explicit environment flag that skips only that compile step; schema generation still invokes `mix run --no-start --no-compile`, so it validates the actual compiled schema snapshot.

The alternative was to remove schema compilation unconditionally, which would make direct `pnpm run relay:check` depend on undocumented prior state.

### Put source-of-truth and advisory checks in the normal gate

`mix verify` and `mix precommit` run Hex and production pnpm advisory audits plus strict OpenSpec spec/change validation. The shell helper delegates to Mix instead of maintaining a second hand-written backend gate. This gives one authoritative sequence and prevents future drift.

### Reject compile-time module cycles

The operator-workflow query resolves the importing schema dynamically only at the Relay global-id boundary, removing the query/schema compile cycle without changing runtime identity behavior. An xref-backed architecture test rejects compile-time cycles while allowing the three existing runtime-only Phoenix and OTP coordination cycles; forcing those runtime relationships through new indirection would increase abstraction without improving compile ownership.

### Remove the resolved review handoff

`code-review-issues-2026-07-09.md` is deleted. It is a dated work note whose findings are all marked resolved, and Git history preserves it if historical investigation is needed. Current requirements remain in OpenSpec.

## Risks / Trade-offs

- **A transient advisory-service outage could fail local verification** → `mix hex.audit` is intentionally a trust gate; failures remain visible rather than silently bypassed.
- **Skipping compilation could validate stale beams** → only the parent Mix gate sets the flag, immediately after warnings-as-errors compilation; standalone schema checks still compile.
- **Moving transaction helpers could alter exception behavior** → add an architecture regression first, retain existing public behavior tests, and run focused waiver/evidence suites before the full gate.
- **A broad dependency update could introduce unrelated behavior** → update only Postgrex from 0.22.2 to 0.22.3 and the required transitive `db_connection` patch from 2.10.1 to 2.10.2.

## Migration Plan

No runtime migration is required. Land the lockfile, verification workflow, internal module extraction, and documentation cleanup together; rollback is a normal Git revert because persistence and public contracts do not change.

## Open Questions

None.
