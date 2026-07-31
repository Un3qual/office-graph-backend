## 1. Correctness Regressions

- [x] 1.1 Add failing active-deprovisioned-active WorkOS directory and SSO lifecycle tests, then restore only the exact retained identity and eligible principal in the owning transaction
- [x] 1.2 Add a failing Relay command-controller test for synchronous variable translation errors, then keep pending state recoverable
- [x] 1.3 Add failing error-classification and nil-private-metadata tests, then centralize constraint matching and preserve non-storage conversation action failures
- [x] 1.4 Add equal-timestamp operator-history and opaque run-identity fixtures, then restore timestamp-plus-ID ordering and the generated Relay Node contract
- [x] 1.5 Add a local-session revalidation query-bound test, then reuse the exact identity basis loaded during human-session resolution

## 2. Test Persistence Simplification

- [x] 2.1 Add cleanup behavior coverage against canonical resources, then replace the 54-resource shadow Ash schema with one test-only canonical hard-delete seam and the narrow Oban cleanup resource
- [x] 2.2 Convert retained persistence failure adapters to one process-scoped test response store, remove per-test Application mutation and unnecessary serialization, and delete checkpoints without consumer-visible failure coverage
- [x] 2.3 Remove the redundant concurrency-support cleanup delegates and update callers to use the owning cleanup module directly

## 3. Quality Gate Simplification

- [x] 3.1 Add a failing scanner test for SQL phrases in non-executable migration literals, then restrict classification to executable SQL-bearing AST positions
- [x] 3.2 Replace debt-inventory generation and remediation bookkeeping with a strict current-occurrence versus approved-exception gate and remove the empty debt inventory
- [x] 3.3 Run ExDNA once through Credo from one current path configuration and remove the duplicate standalone configuration
- [x] 3.4 Derive Relay resource conformance from configured Ash resources, rely on behavior coverage for stable projection Nodes, and remove source-text counting checks
- [x] 3.5 Extract migration parsing from the cross-domain conformance helper into focused migration support and update direct consumers

## 4. Documentation And Frontend Test Quality

- [x] 4.1 Strengthen the session-shell privacy test around the rendered public contract rather than two fixture keys
- [x] 4.2 Remove the archived agent execution plan after confirming its normative decisions are represented in canonical OpenSpec

## 5. Verification And Publication

- [x] 5.1 Run focused backend and frontend tests after each red-green slice, then run formatter and generated-artifact checks
- [x] 5.2 Synchronize the four delta specifications and run strict OpenSpec validation
- [x] 5.3 Run the canonical PostgreSQL 18 repository verification from the final tree and confirm no generated or tracked drift
- [x] 5.4 Review the final stacked diff for unnecessary abstractions and confirm the remediation branch contains only accepted scope
