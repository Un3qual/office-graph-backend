## Why

The quality-boundaries branch implements organization-wide enterprise role
mappings and repository-wide database-access enforcement, but review exposed
three paths where the implementation does not yet satisfy those contracts.
These gaps can prevent valid WorkOS users from signing in and allow ordinary
Elixir aliasing to bypass the raw-SQL approval gate.

## What Changes

- Preserve an explicitly organization-wide external group-role mapping through
  authorized creation and lifecycle management.
- Convert an organization-wide login scope into a selected workspace scope
  before issuing the required workspace-bound Office Graph session.
- Resolve repository aliases in the database-boundary scanner so aliased
  `OfficeGraph.Repo` calls cannot bypass raw-SQL or direct-Ecto enforcement.
- Add focused regression coverage for all three review findings.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `enterprise-directory-sync`: Require authorized mapping management to
  preserve and manage explicit organization-wide scope.
- `workos-enterprise-sso`: Require an organization-wide mapped identity to
  complete login into the transaction-bound workspace.
- `project-quality-gates`: Require the database-boundary Credo scanner to
  recognize aliased repository receivers.

## Impact

The change affects enterprise identity management and WorkOS callback scope
selection in `lib/office_graph`, plus the project-local database-boundary
scanner and its focused tests. It adds no dependency, provider API, raw SQL,
direct Ecto path, or migration.
