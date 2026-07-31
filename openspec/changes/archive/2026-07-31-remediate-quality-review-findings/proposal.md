## Why

The quality-boundaries branch established the intended Ash, Relay, authentication, and database policies, but its implementation also introduced correctness regressions and several maintenance mechanisms that duplicate product structure or obscure failures. This follow-up fixes the validated regressions and leaves each quality rule enforced by the smallest observable boundary that can prove it.

## What Changes

- Restore an exactly matching WorkOS directory and SSO identity after a newer active lifecycle event without weakening conflict handling.
- Keep Relay command submission recoverable when client-side ID translation fails and preserve stable agent-history ordering and opaque-ID test fixtures.
- Preserve real Ash, authorization, programming, and rollback failures instead of classifying them as storage outages; make uniqueness-conflict handling nil-safe and centralized.
- Revalidate local-development sessions from their exact linked identity without scanning and reconstructing every fixture.
- Replace the concurrency-cleanup shadow schema and global production no-op failure hooks with narrow test-owned seams around canonical behavior.
- Reduce database-boundary and architecture enforcement to behavior-based checks, remove the completed debt-inventory lifecycle, and consolidate duplicated ExDNA configuration.
- Split newly added migration conformance logic out of the cross-domain test-support monolith, remove redundant cleanup delegates, strengthen visible session-shell privacy coverage, and remove the archived agent execution plan.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `enterprise-directory-sync`: Define exact in-place restoration for a previously accepted directory identity after a newer active provider event.
- `external-identity-reconciliation`: Allow only the exact compatible disabled WorkOS subject to reactivate once the active directory basis is restored.
- `ecto-sql-boundaries`: Replace completed removal-debt bookkeeping and a shadow cleanup schema with a strict current-occurrence gate and narrow test-owned cleanup seams.
- `project-quality-gates`: Require semantic scanner inputs, one ExDNA configuration source, behavior-focused conformance checks, and durable OpenSpec artifacts free of agent execution choreography.

## Impact

The change affects enterprise identity reconciliation, local session validation, Relay command and projection mapping, test support, Credo/ExDNA configuration, database-boundary inventories, and archived OpenSpec documentation. It adds no dependency and does not change public routes or GraphQL field names.
