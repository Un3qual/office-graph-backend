## 1. Specify Credo Boundary Behavior

- [ ] 1.1 Add failing behavior tests for clean-baseline success and Credo issue mapping for new, changed, stale, malformed-inventory, and parallel-planning diagnostics
- [ ] 1.2 Add a failing integration test proving the project-local check is registered with Credo and can be selected through the focused `--only` invocation

## 2. Implement The Project-Local Credo Check

- [ ] 2.1 Move the planning scanner, database scanner, and inventory gate into the build-only `credo_checks/office_graph/project_boundaries/**` area while preserving their existing behavior tests and fingerprint output
- [ ] 2.2 Implement the all-source Credo check and actionable source-versus-inventory issue mapping
- [ ] 2.3 Register the check through `.credo.exs` without adding a production dependency or compiling Credo code into the production application

## 3. Consolidate Canonical Verification

- [ ] 3.1 Prove the focused Credo check accepts the exact current 896-entry debt baseline without changing either inventory
- [ ] 3.2 Remove the two project-specific Mix aliases, their command-wrapper code and tests, and their duplicate canonical verify entries
- [ ] 3.3 Update verification meta-tests to prove project boundaries run exactly once through Credo

## 4. Verify And Close

- [ ] 4.1 Run formatter, focused project-quality tests, the focused Credo invocation, compilation with warnings as errors, and strict OpenSpec validation
- [ ] 4.2 Run the complete canonical `bin/verify` gate and confirm the worktree and database-access inventories remain unchanged
- [ ] 4.3 Review the final diff for duplicate scanners, product-runtime Credo coupling, changed fingerprints, vague diagnostics, placeholders, and unrelated behavior changes
