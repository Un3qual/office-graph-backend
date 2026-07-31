## Why

The PR review identified security, lifecycle, operability, and bounded-read gaps
in the new enterprise identity and generated Relay paths. These need durable
contract fixes before the branch can be merged.

## What Changes

- Require authenticated TLS peers for production WorkOS HTTP requests.
- Preserve active agent executions and pending approval/context requests ahead
  of terminal history in the generated Relay conversation read.
- Keep WorkOS SSO usable when one of multiple valid directory identity bases is
  deprovisioned, while still revoking the final affected basis.
- Make logout provider-aware and validate each WorkOS session against the exact
  enterprise connection that issued it.
- Add an authorized, operation-correlated directory-binding command to the
  enterprise identity boundary.
- Canonicalize principal email at the Ash write boundary and use the existing
  declarative email identity index for reconciliation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `workos-enterprise-sso`: Require TLS peer verification, connection-bound
  session validation, and provider-aware passive logout.
- `enterprise-directory-sync`: Add authorized directory binding and preserve
  SSO access while another accepted directory identity basis remains active.
- `node-conversations`: Preserve active executions and pending gate requests
  inside the generated Relay history bound.
- `human-authentication`: Maintain canonical principal email and use its
  existing identity index for deterministic account linking without
  full-table expression scans.

## Impact

The change affects WorkOS HTTP transport, enterprise identity and human session
resources, authentication orchestration, generated GraphQL queries and Relay
artifacts, AshPostgres migrations and snapshots, focused backend/frontend
tests, and the canonical OpenSpec contracts listed above.
