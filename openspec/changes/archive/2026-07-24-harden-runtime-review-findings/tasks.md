## 1. Upgrade Safety

- [x] 1.1 Add a failing migration test for a legacy `openspec-review` row.
- [x] 1.2 Add and verify an idempotent forward reconciliation migration.

## 2. Durable Runtime

- [x] 2.1 Add a failing cancellation-race test and revalidate the claim before dispatch.
- [x] 2.2 Add a failing recovery configuration test and enable orphaned-job recovery.
- [x] 2.3 Strengthen generated API malformed-link coverage.

## 3. Run Activity Pagination

- [x] 3.1 Add a failing test for a focused activity continuation operation.
- [x] 3.2 Implement the focused Relay query, hook, component use, and generated artifact.

## 4. Contract Reconciliation

- [x] 4.1 Apply the approved clarifications to durable specifications.
- [x] 4.2 Apply matching clarifications to the unmerged archived change and design.

## 5. Verification

- [x] 5.1 Run focused backend and frontend tests plus strict OpenSpec validation.
- [x] 5.2 Run the full project verification suite.
- [x] 5.3 Run a fresh local CodeRabbit review and resolve any remaining actionable findings.

## 6. Delivery

- [x] 6.1 Commit the verified implementation and specification changes.
- [x] 6.2 Push the branch to the existing pull request.
