## 1. Regression Coverage

- [x] 1.1 Add failing authorized-management coverage for explicit organization-wide connection and mapping scope
- [x] 1.2 Add failing end-to-end WorkOS login coverage for a principal authorized only by an organization-wide mapping
- [x] 1.3 Add failing scanner coverage for raw SQL and direct Ecto invoked through explicit repository aliases

## 2. Implementation

- [x] 2.1 Preserve explicit nil management scope and require authority at the selected target scope
- [x] 2.2 Allow organization-wide external login scope to satisfy the transaction-bound preferred workspace
- [x] 2.3 Resolve explicit repository aliases before database call classification

## 3. Verification and Publication

- [x] 3.1 Run focused enterprise identity and project-quality tests
- [x] 3.2 Run formatting, strict OpenSpec validation, and canonical project verification
- [x] 3.3 Sync and archive the completed OpenSpec change, then commit and push the verified branch
