## Why

Local CodeRabbit review of the quality-boundary pull request found six
validated contract gaps in Relay refetch, enterprise role scope, directory
payload validation, external identity ownership, conflict evidence, and
authentication evidence. These gaps should be closed before merge so the
implementation matches the accepted Ash, enterprise identity, and session
contracts.

## What Changes

- Include every generated GraphQL resource domain in root Relay node refetch.
- Treat active organization-wide external group-role mappings as valid
  organization scopes and as authority within any workspace in that
  organization.
- Reject malformed or over-limit optional WorkOS directory fields instead of
  silently erasing them.
- Prevent lifecycle actions from reassigning an external identity link to a
  different principal.
- Return the specific verified-identifier conflict reason when existing email
  links have no compatible principal.
- Constrain authentication event and result values to the bounded lifecycle
  vocabulary used by session evidence.
- Add focused regression coverage and retain the canonical verification gate.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ash-api-surface`: Require root Relay node refetch to include every domain
  that contributes generated GraphQL resources.
- `enterprise-directory-sync`: Clarify organization-wide mapping inheritance
  and strict validation of present optional directory fields.
- `external-identity-reconciliation`: Make external identity ownership
  immutable through lifecycle changes and preserve the specific conflict
  reason.
- `session-and-token-model`: Require bounded authentication event and result
  values.

## Impact

Affected areas are the shared GraphQL node resolver, enterprise authorization
fact queries, WorkOS directory normalization, external identity lifecycle and
reconciliation actions, authentication event validation, their focused tests,
and the corresponding canonical OpenSpec requirements. No public route,
dependency, migration, or raw SQL change is required.
