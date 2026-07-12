## 1. Audit Record And Baseline

- [x] 1.1 Write the evidence-backed project audit with severity, affected contracts, fix disposition, long-file judgment, and explicitly deferred structural gaps.
- [x] 1.2 Capture clean Nix baseline evidence for OpenSpec, dependency advisories, backend checks, the complete backend suite, and frontend verification, including the canonical-alias omission reproduction.

## 2. Canonical Quality Gate

- [x] 2.1 Add a regression for full-suite execution, then make verify/precommit invoke one complete ExUnit run and use non-mutating lockfile checks.
- [x] 2.2 Make `bin/verify` the canonical all-layer entry point, isolate Compose/port/test-database identity per worktree, and update local documentation.
- [x] 2.3 Add tracked Nix-based CI, strict OpenSpec and placeholder-purpose checks, backend/frontend advisory checks, and production build smoke coverage.
- [x] 2.4 Update vulnerable dependencies and add regression coverage for exact runtime boolean parsing.

## 3. Backend Correctness

- [x] 3.1 Add a failing late-observation regression, then make failed observations invalidate a previously verified run while later successful observations preserve verified state.
- [x] 3.2 Add a failing duplicate-result-slot regression, then preflight the locked run/check slot and return one stable conflict without creating partial evidence.
- [x] 3.3 Persist reconstructable allow/deny decisions for waiver authorization even when later domain validation rejects the command; sanitize reference-validator infrastructure failures.
- [x] 3.4 Make the capability-backfill rollback non-destructive and prove pre-existing capability/grant rows survive up/down.

## 4. Shared Command Semantics

- [ ] 4.1 Replace the duplicate GraphQL/JSON command input parsers with one transport-neutral parser and preserve transport integration tests.
- [ ] 4.2 Replace divergent error classifiers with one safe registry, add every public conflict/validation outcome, recursively sanitize metadata, and table-drive GraphQL/JSON parity.
- [ ] 4.3 Teach the frontend conflict registry to refresh authoritative state for the shared concurrency outcomes.

## 5. Operator Projection And API Safety

- [ ] 5.1 Project and render policy-safe source/proposal summaries so pending work can be distinguished and reviewed before apply.
- [ ] 5.2 Project complete typed run/evidence command-option bundles and remove browser-side reconstruction of domain relationships/defaults.
- [ ] 5.3 Bound growing packet/run/relationship collections with Relay connections or compact summaries, support incremental reads, and reject negative pagination while preserving zero-item semantics.
- [ ] 5.4 Remove the retired unreleased `operatorInbox` field and regenerate the GraphQL schema and Relay artifacts.

## 6. Frontend Correctness And Accessibility

- [ ] 6.1 Make Relay queries and mutations abort their underlying HTTP request on disposal and prove late payloads are ignored.
- [ ] 6.2 Preserve all command field errors, map them to controls, render accessible inline feedback and a summary, and focus the first invalid control.
- [ ] 6.3 Use client-side navigation for internal links, configure safe DateTime scalar typing, remove blind casts, and replace internal evidence jargon and stale queue copy.
- [ ] 6.4 Remove dead operator hooks/exports, unused styles and StyleX tooling, then add AST-aware lint/import-boundary enforcement to frontend verification.

## 7. Maintainability Refactoring

- [ ] 7.1 Move the durable-delivery test worker into test support and split the multiple top-level proposed-change modules into cohesive files.
- [x] 7.2 Extract explicit run lifecycle reduction and evidence result-slot policy seams without fragmenting their transactions.
- [ ] 7.3 Split the largest backend test modules around behavior domains and shared support while preserving assertions.
- [ ] 7.4 Split the operator/packet route tests and global styles around route ownership and shared fixtures/tokens.
- [ ] 7.5 Replace high-risk source-string architecture assertions with behavioral, introspection, or TypeScript AST checks where executable contracts exist.

## 8. Documentation And Completion

- [x] 8.1 Replace all canonical generated purpose placeholders and mark the discovery-era project plan historical with current-source pointers.
- [ ] 8.2 Run focused red/green evidence for every behavior fix, then the canonical gate twice with varied seeds and confirm a clean worktree.
- [ ] 8.3 Independently review the complete stacked diff, resolve every material finding, validate the OpenSpec change strictly, and archive it.
- [ ] 8.4 Commit and push the semantic branch, open a non-draft PR targeting the latest open PR branch, and record deferred structural gaps in the PR body.
