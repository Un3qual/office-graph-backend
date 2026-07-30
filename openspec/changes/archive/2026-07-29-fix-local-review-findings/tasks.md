## 1. Add Regression Coverage

- [x] 1.1 Add generated Relay node refetch coverage for normalized intake events and proposed graph changes
- [x] 1.2 Add organization-wide external mapping login-scope and workspace-authorization coverage
- [x] 1.3 Add malformed optional WorkOS directory field rejection coverage
- [x] 1.4 Add external identity ownership and verified-identifier conflict coverage
- [x] 1.5 Add authentication event and result vocabulary rejection coverage

## 2. Implement The Accepted Review Fixes

- [x] 2.1 Register all generated GraphQL resource domains with the shared node resolver
- [x] 2.2 Include organization-wide mappings in login-scope and workspace authorization queries
- [x] 2.3 Propagate optional WorkOS directory field validation failures
- [x] 2.4 Remove principal reassignment from lifecycle transitions and return the specific conflict reason
- [x] 2.5 Validate authentication event and result values at the Ash resource boundary

## 3. Verify And Publish

- [x] 3.1 Run formatting, focused tests, compilation with warnings as errors, and strict change validation
- [x] 3.2 Run canonical `bin/verify`, review the final diff, sync and archive the OpenSpec change, commit, and push PR #34
