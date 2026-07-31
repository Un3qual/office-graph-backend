## Why

Fresh PR 34 review found four boundary gaps that can hide direct database access, leave local development fixtures unrepaired, misclassify retryable identity-storage outages, or buffer an unbounded WorkOS error response. These gaps need regression-backed fixes before the branch is extended or merged.

## What Changes

- Bound every production WorkOS HTTP response while it is received, including non-success responses.
- Preserve active enterprise-connection read failures as retryable enterprise identity storage failures through WorkOS login preparation and code exchange.
- Reconcile each manifest-owned local development fixture principal to its exact expected role assignment set when the explicit seed command is replayed.
- Classify explicit repository connection checkout as direct Ecto access in the canonical project-boundary scanner.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `workos-enterprise-sso`: bound non-success transport responses and preserve retryable connection-storage failures.
- `bootstrap-and-local-identity-lab`: make explicit fixture seed replay remove role assignments outside the fixture manifest.
- `project-quality-gates`: classify direct repository connection checkout as direct Ecto access.

## Impact

The change affects the WorkOS production HTTP adapter, enterprise connection lookup error mapping, local development authorization setup, the project-local Credo database-boundary scanner, focused backend tests, and canonical OpenSpec requirements. A bounded streaming HTTP client dependency may replace `:httpc` if the pinned runtime cannot enforce the limit for non-success responses.
