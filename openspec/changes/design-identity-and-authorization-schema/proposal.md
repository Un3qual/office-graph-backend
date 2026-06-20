## Why

The current OpenSpec set defines strong authorization semantics but does not
yet name the concrete identity, authorization, scope, policy fact, and
credential table families that first migrations must account for. This change
removes that blocker before Phoenix, Ash, Ecto, Boundary, API, integration, or
agent-runtime code generation begins.

## What Changes

- Introduce a design-only identity and authorization schema inventory for
  principals, profiles, external identities, scopes, closure-table inheritance,
  roles, capabilities, role assignments, explicit grants, organization facts,
  sensitivity labels, policy bundle versions, fact versions, and credential
  metadata.
- Decide that scope hierarchy storage starts with an adjacency list plus
  closure table, not `ltree` and not materialized path as the sole model.
- Define scope move behavior, inheritance impact recording, and authorization
  explanation cache invalidation/recomputation.
- Keep authorization policy semantics in `design-enterprise-governance` while
  this change owns concrete persistence inventory for the facts those policies
  evaluate.
- Keep persistence architecture in `design-persistence-model` while referencing
  this change as the companion identity/authorization inventory required before
  first migrations.
- This change is design-only and does not implement migrations, Phoenix, Ash,
  Ecto, GraphQL, JSON API, Boundary, Oban, integrations, or agent runtime code.

## Capabilities

### New Capabilities

- `identity-authorization-inventory`: concrete table-family inventory for
  identity, authorization, organization facts, sensitivity, policy facts, and
  credential metadata.
- `scope-hierarchy-storage`: adjacency-list and closure-table storage model for
  scope inheritance and scope moves.
- `principal-role-capability-model`: durable principal, role, capability,
  assignment, group/team, and explicit-grant facts.
- `policy-fact-versioning`: immutable policy bundle versions and optional fact
  version anchors for sensitive authorization decisions.
- `credential-metadata-model`: secret-free credential metadata, lifecycle,
  scope, capability, rotation, revocation, and audit linkage.

### Modified Capabilities

- None. No durable specs have been archived yet; this change adds active
  design deltas and cross-links only.

## Impact

- Affects OpenSpec planning and future database/resource generation only.
- Requires `design-persistence-model` to treat this inventory as a required
  companion before first migrations.
- Requires `design-enterprise-governance` to reference this inventory for
  concrete authorization facts without duplicating table ownership.
- Creates no runtime dependencies and no application code.
