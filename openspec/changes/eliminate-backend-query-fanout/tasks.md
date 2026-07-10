## 1. Query-Count Regression Baselines

- [x] 1.1 Add a failing packet-creation scaling test that proves source-reference and packet-required-check validation reads and inserts grow per input today.
- [x] 1.2 Add a failing run-start scaling test that proves run-required-check validation reads and inserts grow per input today.
- [x] 1.3 Add bounded read-scaling coverage for operator run-state children and generated GraphQL packet/run lists, preserving the existing operator-inbox query budget.

## 2. Batch-Aware Ash Validation

- [x] 2.1 Add focused failing tests for batched same-scope reference validation, including missing, cross-scope, and graph-item identity failures.
- [x] 2.2 Implement `ValidateSameScopeReferences.batch_change/3` with one batched read per referenced resource and shared single/bulk validation helpers.
- [x] 2.3 Add focused failing tests for batched run required-check validation and preserve packet-mismatch errors.
- [x] 2.4 Implement `ValidateRunRequiredCheckContract.batch_change/3` with batched run and packet-required-check reads while retaining the non-packet-backed guard.

## 3. Ash-Native Bulk Collection Writes

- [x] 3.1 Add an `OfficeGraph.Repo` Ash bulk-create helper that handles empty inputs, returns records in input order, stops on error, and rolls back through the existing transaction boundary.
- [x] 3.2 Replace packet source-reference and packet-required-check create loops with the bulk helper and make the packet scaling test pass.
- [x] 3.3 Add invalid-middle-item coverage proving packet creation cannot persist a partial link collection.
- [x] 3.4 Replace run required-check create loops with the bulk helper and make the run scaling test pass.
- [x] 3.5 Add invalid-middle-item coverage proving run creation cannot persist a partial required-check collection.

## 4. Verification And Documentation

- [x] 4.1 Run focused query-count, validator, work-packet, run, projection, and generated API tests from the project Nix shell.
- [ ] 4.2 Run `mix format --check-formatted`, `mix compile --warnings-as-errors`, and the full project verification command from the project Nix shell.
- [ ] 4.3 Run strict OpenSpec validation and `git diff --check`.
- [x] 4.4 Record measured per-source query ceilings and any accepted Ash batch boundary in implementation notes or test comments.
