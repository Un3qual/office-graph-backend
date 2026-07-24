## Why

The run-review definition reconciliation preserves legacy bindings, but those
bindings can still reference workspace-scoped agent roles that lack the
canonical model and governed-output capabilities. Upgraded installations must
remain invocable without requiring an operator to replay the binding command.

## What Changes

- Reconcile the canonical run-review capabilities onto roles assigned to
  existing bound agent principals in the binding's exact workspace scope.
- Keep the forward migration idempotent and preserve definition, binding,
  principal, role, assignment, and lifecycle identities.
- Add migration regression coverage for a legacy binding with the former
  runtime-only authority.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-definitions`: Require the forward legacy-definition reconciliation to
  restore the canonical authority of existing run-review bindings.

## Impact

This affects the run-review reconciliation migration, its migration regression
test, and the durable agent-definitions contract. It does not add an
administration API or broaden grants beyond roles already assigned to bound
agent principals in their persisted workspace scope.
