## Context

Legacy databases can contain an active `openspec-review` binding whose agent
principal already has a workspace-scoped system role. The reconciliation
migration preserves that binding and definition identity, but the role was
created before the canonical run-review model and governed-output capabilities
were added.

## Goals / Non-Goals

**Goals:**

- Make existing bindings immediately usable after the forward migration.
- Limit new grants to the exact roles already assigned to bound agent
  principals in each binding's persisted workspace scope.
- Preserve all existing identities and lifecycle states.
- Keep repeated migration execution conflict-safe.

**Non-Goals:**

- Creating or reactivating bindings, principals, roles, or assignments.
- Granting capabilities to owners, unrelated agent roles, or broader
  organization scopes.
- Adding a runtime repair path or administration surface.

## Decisions

- Extend the existing unreleased reconciliation migration because it has not
  shipped and already owns the legacy-to-canonical upgrade.
- Select active bindings and role assignments through the binding's agent
  principal, organization, and workspace, then require the deterministic
  workspace system role key. This avoids granting authority through inactive
  bindings or unrelated roles that happen to be assigned to the same
  principal.
- Insert only the three capabilities newly required by the canonical binding
  contract. Existing runtime and skeleton grants remain untouched.
- Use the existing `(role_id, capability_id)` conflict boundary so the
  migration is safe to run repeatedly.

## Risks / Trade-offs

- A malformed legacy binding without its original system role remains
  unusable. This is fail-closed and preferable to manufacturing missing
  identity or authorization records during reconciliation.
- Editing the unreleased migration is safe for this branch, but the regression
  test must run it twice to preserve idempotency.
