## 1. Verification Baseline

- [x] 1.1 Add a failing architecture regression that requires waiver execution to live behind a focused internal module.
- [x] 1.2 Update Postgrex to the patched 0.22.3 lock and confirm the advisory clears.
- [x] 1.3 Make the Relay schema checker skip redundant compilation only when the parent Mix gate declares compiled beams.
- [x] 1.4 Add dependency-advisory and strict OpenSpec validation to the verify and precommit aliases, with one authoritative shell entrypoint.
- [x] 1.5 Remove the GraphQL schema/query compile cycle and add a regression that rejects future compile-time module cycles.
- [x] 1.6 Prevent the focused architecture alias from shadowing the full backend test task in project verification.

## 2. Verification Context Refactor

- [x] 2.1 Extract shared scoped-command transaction primitives into an internal verification support module.
- [x] 2.2 Extract governed waiver execution into `OfficeGraph.Verification.Waiver` while preserving the existing context API.
- [x] 2.3 Run focused waiver, evidence, boundary, static-analysis, and type checks.

## 3. Repository Hygiene And Delivery

- [x] 3.1 Remove the resolved dated code-review handoff and verify no live documentation references it.
- [ ] 3.2 Run the complete project verification, strict OpenSpec validation, advisory audit, and diff checks.
- [ ] 3.3 Archive the completed OpenSpec change and validate the resulting specs strictly.
- [ ] 3.4 Commit and publish a ready-for-review PR stacked on `codex/archive-operator-command-loop`.
