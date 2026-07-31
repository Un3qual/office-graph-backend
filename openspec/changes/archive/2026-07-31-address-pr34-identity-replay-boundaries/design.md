## Context

Directory users retain whether their reconciliation created or reused a
principal, but deprovisioning currently consults only the origin of the user
being processed. That per-user fact is insufficient after multiple directory
users converge on one principal. Directory binding already uses an Ash no-op
upsert for concurrent safety, but its postcondition validates only ownership and
operation identity, not the material binding input. The project-local database
scanner resolves repository receivers correctly but its operation inventory
omits rollback control.

The fixes must remain inside Ash-owned actions and queries. No raw SQL, direct
Ecto mutation, explicit `Repo.transaction`, new dependency, or migration is
required.

## Goals / Non-Goals

**Goals:**

- Disable a directory-created principal when its last accepted active identity
  basis ends, even when the last directory user reused that principal.
- Preserve exact directory-binding replay while rejecting changed material
  input under the same operation identity.
- Close the receiver-aware `Repo.rollback` scanner gap without flagging
  unrelated modules.
- Cover each behavior with a focused regression.

**Non-Goals:**

- Redesign principal or directory-user provenance storage.
- Add a general directory lifecycle update command.
- Expand the database scanner beyond the concrete reviewed operation.

## Decisions

### Derive principal provenance from retained directory users

Before calling the identity deprovision action, the enterprise-directory action
will use an Ash existence query to determine whether any retained directory
user for the principal has `principal_origin == "created"`. It will pass that
durable principal-level fact instead of treating the current user's origin as
principal provenance. The identity action will continue to lock the principal,
disable the current link, and check all active linked identity bases before
changing principal status, preserving its existing serialization boundary.

This reuses the existing in-table provenance and avoids a duplicate principal
column plus backfill. Checking only the current user was rejected because it is
the source of the bug; inferring creation from active links was rejected because
deprovisioning intentionally retains disabled historical links.

### Validate the complete no-op upsert result

The directory binding command will keep the Ash no-op upsert, which atomically
selects the one provider-directory row under concurrent calls. After the upsert,
the command will distinguish three cases: exact material replay succeeds,
different ownership fails closed, and the same operation with changed status or
provider timestamp returns the established command-idempotency conflict. No
fields are silently updated during replay.

Updating lifecycle fields implicitly was rejected because a retry must not turn
an immutable create/bind command into an undocumented lifecycle mutation.

### Extend the resolved-receiver operation set

`rollback` will join the existing direct repository operation inventory. The
scanner's existing alias resolution remains the source of receiver truth, so
direct and explicitly aliased `OfficeGraph.Repo` calls are classified while
lookalike calls on unrelated modules remain ignored.

## Risks / Trade-offs

- **Historical provenance is represented by directory-user rows** -> Query the
  retained in-table history through Ash and add a shared-principal lifecycle
  regression that proves both intermediate and last-basis behavior.
- **Replay comparison can drift when material fields are added** -> Keep the
  requested binding field list and equality helper adjacent to the bind command,
  and test both lifecycle status and provider timestamp changes.
- **Operation-name scanning can create false positives** -> Reuse receiver-aware
  classification and cover unrelated `rollback` receivers explicitly.
