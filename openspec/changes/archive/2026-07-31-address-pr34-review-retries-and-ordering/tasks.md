## 1. Regression Proofs

- [x] 1.1 Add scanner coverage for fully qualified, aliased, imported, bang, and streaming Postgrex and Ecto SQL-adapter APIs.
- [x] 1.2 Add a gate-expiry worker regression proving storage failure snoozes at the nominal final attempt while permanent errors do not.
- [x] 1.3 Add directory lifecycle coverage for distinct equal-time events processed in reverse worker order and exact replay.
- [x] 1.4 Repeat the previously flaky committed-concurrency modules across multiple seeds.

## 2. Root-Cause Fixes

- [x] 2.1 Classify the complete pinned Postgrex and Ecto SQL-adapter operation families at the resolved receiver boundary.
- [x] 2.2 Keep transient gate-expiry storage failures retryable through the same unique Oban job.
- [x] 2.3 Persist and compare durable directory receipt order for users, groups, and memberships, including latest-history sorting.
- [x] 2.4 Generate one forward AshPostgres migration and updated resource snapshots without raw SQL or old-migration edits.
- [x] 2.5 Restore direct scoped sandbox checkout for synchronous concurrency callbacks.

## 3. Verification And Delivery

- [x] 3.1 Run focused scanner, agent-runtime, directory lifecycle, migration, formatting, and compile checks.
- [x] 3.2 Run canonical project verification, strict OpenSpec validation, and `git diff --check`.
- [x] 3.3 Sync the three delta specs and prepare the completed change for archive.
- [x] 3.4 Prepare replies for the three current bot threads with verification evidence and no post-push refresh.
