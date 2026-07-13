## Context

Office Graph has strong local static analysis and extensive tests, but the audit found that the canonical Mix alias invokes a focused `test` alias before the full suite. Mix's one-invocation task semantics then skip roughly 329 of 399 declared behavioral tests. The repository also has two partial verification entry points, no tracked CI, shared Compose/database identities across worktrees, and no durable-spec placeholder check.

The same audit traced current product defects across run reduction, evidence acceptance, authorization auditing, transport classification, operator projections, and Relay form/network behavior. It also found duplicated command parsers and error registries, test-only production code, dead frontend tooling and UI paths, and several very large files. Existing OpenSpec contracts already define the correct product behavior for those defects, so this change adds only the missing project-quality-gate capability rather than rewriting product requirements.

## Goals / Non-Goals

**Goals:**

- Make a single Nix-backed command prove the actual backend, frontend, OpenSpec, dependency, and build state without modifying tracked files.
- Make local gates safe to run concurrently from multiple worktrees.
- Restore current behavior to accepted product contracts with regression-first fixes.
- Centralize transport-neutral parsing and safe error semantics while keeping GraphQL and JSON envelope ownership separate.
- Move command choices and safe summaries to backend projections, bound naturally growing reads, and make frontend errors and cancellation semantically complete.
- Remove confirmed dead or duplicated code and split only boundaries whose cohesion improves measurably.
- Preserve a detailed audit record, including issues intentionally requiring later product changes.

**Non-Goals:**

- Designing organization-scoped durable events and system operations with nullable workspace, principal, session, and subject version.
- Replacing one-row verification result slots with append-only supersession history.
- Introducing a typed relationship registry and historical graph-relationship lifecycle.
- Mechanically splitting every file above an arbitrary line count, rewriting immutable migrations, or removing accepted skeletal bounded-context modules.
- Replacing the approved request-scoped trusted projection authorization model.

## Decisions

### Use one complete test invocation

`mix verify` will invoke the full `test` alias once. Focused architecture tests remain available as a developer command but will not precede the full suite in a composite alias. The precommit alias will delegate to the same non-mutating verification sequence.

Alternative considered: re-enable Mix's test task between aliases. This would compile/start the test environment twice and preserve an unnecessary ordering hazard.

### Make the repository script the operational entry point

`bin/verify` will own Compose readiness and per-worktree isolation, then call the complete Mix gate inside the already-entered Nix environment. The README and CI will invoke it through the pinned flake. Callers with external PostgreSQL can opt out and provide explicit connection and partition variables.

Alternative considered: put Docker orchestration inside Mix. That would couple application tooling to one container runtime and make database-only development commands surprising.

### Test stable behavior, not implementation spelling

Each correctness fix starts with a regression that fails for the observed behavior. Source-string architecture checks will be replaced where an executable behavior, schema introspection, or TypeScript AST rule can express the same contract. Heuristic checks that remain will be named as heuristics and will not claim runtime proof.

### Keep transactions cohesive while extracting policy and reduction seams

Run lifecycle reduction will become an explicit, testable state decision rather than a terminal-state shortcut. Evidence acceptance will preflight the locked result slot before creating dependent records. Shared scoped locking may remain close to the transaction; the audit will not split transactional code merely to reduce line count.

Authorization policy evaluation will persist its allow/deny decision independently of later domain command success. Domain outcome auditing remains a separate concern so an allowed-but-stale waiver is reconstructable without falsely claiming that the waiver succeeded.

### Share command semantics below the transport adapters

One transport-neutral input schema/parser and one safe command-error classifier will define stable codes, categories, safe details, fields, and metadata. GraphQL and JSON modules will adapt those values into their own envelopes/statuses. Nested reasons will be recursively sanitized. This removes proven drift without merging transport controllers or serializers.

### Project complete operator choices

Operator read models will expose policy-safe source/proposal summaries and typed command-option bundles containing the complete stable identifiers/defaults for one valid choice. Forms will not reconstruct domain relationships from parallel raw arrays. Naturally growing collections will use bounded Relay connections or compact summaries, with detail fetched separately.

### Delete only evidence-backed slop

The change will remove code with no production caller, duplicated parsers/classifiers, unused styles and StyleX transforms with no StyleX usage, stale unreleased GraphQL fields, and test workers compiled into production. Large generated Relay artifacts, declarative schema modules, coherent migrations, and accepted boundary markers remain intact. Oversized tests will be split around behavior domains and shared fixtures only after behavior changes land, to avoid obscuring regression work.

### Record structural gaps rather than hiding scope expansion

The audit report will retain the three larger accepted-contract gaps listed as non-goals with evidence and recommended follow-up boundaries. They will not be implemented partially in this PR because each requires data migration, compatibility, and authorization decisions that are independent of the confirmed quality defects.

## Risks / Trade-offs

- **[Risk] The canonical gate becomes slower.** → Cache Nix, Hex, Mix, and pnpm artifacts in CI; keep focused developer aliases while making the merge gate complete.
- **[Risk] Per-worktree port derivation can collide.** → Allow explicit overrides, include a stable worktree-derived partition, and fail clearly if the selected port is occupied by another project.
- **[Risk] Shared error classification changes an edge-case code.** → Table-drive both transports over the same public outcomes and preserve existing stable codes unless the current fallback is the defect.
- **[Risk] Projection pagination changes generated Relay artifacts.** → Regenerate from the schema and cover page boundaries, zero/negative arguments, and incremental UI reads.
- **[Risk] Cleanup removes a seemingly dormant extension point.** → Require repository-wide caller evidence and accepted-spec review before deletion; retain extension points named by active contracts.
- **[Risk] Large test-file moves make review noisy.** → Commit behavior fixes first, then perform isolated mechanical splits with unchanged assertions and focused/full-suite evidence.

## Migration Plan

1. Land the audit artifacts and gate contract.
2. Repair the canonical gate, isolation, dependency advisory, CI, spec hygiene, and runtime boolean parsing.
3. Land backend correctness fixes with migrations and red/green regressions.
4. Land shared transport semantics and operator projection changes, regenerate schema/Relay artifacts, and update frontend behavior.
5. Remove confirmed dead/duplicated code and split selected test/support files in isolated commits.
6. Run the canonical gate from a clean worktree, independently review the complete stacked diff, then archive this OpenSpec change.

Rollback is commit-scoped. The capability rollback migration is deliberately non-destructive because migration-created rows cannot be distinguished from pre-existing or later authorization data.

## Open Questions

None for this change. The deferred organization-scoped delivery, verification supersession, and typed relationship contracts require separate OpenSpec designs.
