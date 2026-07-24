## 1. Upgrade Safety

- [ ] 1.1 Add a failing migration test for a legacy `openspec-review` row.
- [ ] 1.2 Add and verify an idempotent forward reconciliation migration.

## 2. Durable Runtime

- [ ] 2.1 Add a failing cancellation-race test and revalidate the claim before dispatch.
- [ ] 2.2 Add a failing recovery configuration test and enable orphaned-job recovery.
- [ ] 2.3 Strengthen generated API malformed-link coverage.

## 3. Run Activity Pagination

- [ ] 3.1 Add a failing test for a focused activity continuation operation.
- [ ] 3.2 Implement the focused Relay query, hook, component use, and generated artifact.

## 4. Contract Reconciliation

- [ ] 4.1 Apply the approved clarifications to durable specifications.
- [ ] 4.2 Apply matching clarifications to the unmerged archived change and design.

## 5. Verification

- [ ] 5.1 Run focused backend and frontend tests plus strict OpenSpec validation.
- [ ] 5.2 Run the full project verification suite.
- [ ] 5.3 Run a fresh local CodeRabbit review and resolve any remaining actionable findings.

## 6. Delivery

- [ ] 6.1 Commit the verified implementation and specification changes.
- [ ] 6.2 Push the branch to the existing pull request.
