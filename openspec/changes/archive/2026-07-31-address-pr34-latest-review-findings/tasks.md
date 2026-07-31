## 1. Regression Proofs

- [x] 1.1 Add and run a failing scanner regression for fully qualified and aliased Ecto query fragments.
- [x] 1.2 Add and run a failing WorkOS transport regression proving successful responses use bounded controlled streaming.
- [x] 1.3 Add and run a failing directory lifecycle regression for exact active-deleted-active identity restoration.
- [x] 1.4 Add and run a failing adapter contract regression for multi-capability approval-required manifests while preserving non-approval capability sets.

## 2. Root-Cause Fixes

- [x] 2.1 Classify Ecto query API fragment operations at the resolved remote-call boundary.
- [x] 2.2 Receive successful WorkOS responses incrementally with declared-length, accumulated-size, cancellation, and timeout bounds.
- [x] 2.3 Restore only the exact retained directory link and eligible principal under the reconciliation action's existing locks.
- [x] 2.4 Enforce the one-capability approval invariant during adapter manifest validation.

## 3. Verification And Delivery

- [x] 3.1 Verify the two earlier outside-diff worker retry and relationship validity findings remain covered and passing.
- [x] 3.2 Run focused backend tests, formatter, strict OpenSpec validation, canonical project verification, and `git diff --check`.
- [x] 3.3 Sync the four delta specs into canonical specifications and prepare the completed change for archive.
- [x] 3.4 Prepare a commit-ready PR 34 patch and thread-reply evidence; publication follows archive without a post-push refresh.
