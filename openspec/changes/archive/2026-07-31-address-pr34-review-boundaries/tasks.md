## 1. Regression Coverage

- [x] 1.1 Add and run a failing WorkOS transport regression for an oversized non-success response received in chunks.
- [x] 1.2 Add and run a failing local fixture replay regression proving unexpected role assignments are removed for every manifest-owned fixture class.
- [x] 1.3 Add and run a failing database-boundary scanner regression for direct and aliased Repo checkout without unrelated-receiver false positives.
- [x] 1.4 Add and run a failing WorkOS login regression proving an active-connection Ash storage failure remains transient.

## 2. Root-Cause Fixes

- [x] 2.1 Replace the WorkOS `:httpc` receive loop with bounded all-status Req streaming and preserve the adapter response contract.
- [x] 2.2 Reconcile exact local fixture role assignments through a transaction-enabled Ash action invoked only by explicit seed setup.
- [x] 2.3 Extend receiver-aware Repo operation classification to cover connection checkout.
- [x] 2.4 Preserve active-connection Ash read failures as enterprise identity storage unavailability through WorkOS login preparation and exchange.

## 3. Verification

- [x] 3.1 Run focused regressions, formatting, strict OpenSpec validation, and `git diff --check`.
- [x] 3.2 Run the canonical `./bin/verify` gate and review the final diff for unnecessary abstractions or adjacent scope.
