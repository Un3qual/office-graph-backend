## Why

The latest review of PR 34 found four remaining boundary mismatches: one raw-SQL spelling bypasses the repository scanner, successful WorkOS responses are bounded only after buffering, exact directory identities cannot recover from legitimate reprovisioning, and approval-required adapters can declare more capabilities than one durable gate represents. These gaps should close on the base PR so its enforced contracts match its runtime behavior.

## What Changes

- Classify fully qualified and aliased `Ecto.Query.API.fragment` and `unsafe_fragment` calls as repository-authored raw SQL.
- Enforce the WorkOS success-response byte limit while the HTTP transport receives the body instead of after the full body is buffered.
- Restore only the exact retained WorkOS directory identity after a matching newer active event, including a directory-created principal when safe.
- Fail closed when an approval-required adapter manifest declares more than one capability, matching the existing one-request, one-capability durable approval model.
- Keep previously addressed outside-diff worker retry and relationship-validity findings covered by their existing regression tests.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `project-quality-gates`: Recognize fully qualified or aliased Ecto query fragment calls as raw SQL.
- `workos-enterprise-sso`: Bound successful WorkOS response bodies during transport receipt.
- `enterprise-directory-sync`: Restore an exact retained directory identity after legitimate reprovisioning without relaxing conflict checks.
- `agent-approval-requests`: Require approval-gated adapter steps to request exactly one capability until the durable gate model explicitly supports capability sets.

## Impact

Affected areas are the project database-boundary scanner and tests, the production WorkOS HTTP adapter, enterprise identity reconciliation, adapter-manifest validation, focused regression coverage, and the four canonical OpenSpec capabilities above. No public endpoint, new dependency, raw SQL occurrence, or database migration is required.
