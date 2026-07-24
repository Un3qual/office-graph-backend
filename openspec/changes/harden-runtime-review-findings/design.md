## Context

The reviewed batch spans the durable agent worker, an installed definition,
Oban recovery, Relay pagination, and product contracts. The current design is
sound, but upgrade history and two narrow worker timing windows were not fully
represented, while activity pagination reused an unnecessarily broad query.

## Goals / Non-Goals

**Goals:**

- Make upgrades converge on the same canonical definition as fresh databases.
- Close cancellation and orphan-job timing windows without adding another job
  or output-delivery subsystem.
- Keep incremental activity reads proportional to the requested page.
- Make the durable specs precise enough to distinguish the intended cases.

**Non-Goals:**

- Add OpenSpec as a runtime or product capability.
- Introduce shared resolver, route-selection, or test-helper abstractions.
- Expand agent authority, credential snapshots, or conversation replay models.

## Decisions

1. Add a forward, idempotent migration that renames the legacy definition when
   safe and canonicalizes `run-review`. Editing only the historical migration
   cannot repair already-upgraded databases.
2. Treat a claim as provisional until immediately before adapter dispatch. The
   worker re-reads the request and execution and dispatches only when both are
   still running under the claimed lease.
3. Recover an interrupted execution through Oban Lifeline. The existing job is
   the durable retry carrier, so an outbox or second retry job would duplicate
   ownership.
4. Keep the root run-detail query for the initial activity page and add a
   focused query for continuation pages.
5. Update durable and in-flight archived specs together so this unmerged batch
   does not archive stale wording.

## Risks / Trade-offs

- A cancellation can still arrive after the final state check but during the
  external call; the adapter cancellation signal remains the required handling
  for that unavoidable boundary.
- Lifeline recovery is timeout-based, so node-loss recovery is not immediate;
  the configured interval is bounded and avoids parallel execution.
- A second Relay operation adds generated artifacts, but prevents every
  continuation page from re-fetching the complete run-detail graph.

## Migration Plan

Deploy the forward migration before relying on the canonical definition. It is
safe to rerun and preserves the existing definition identity when upgrading the
normal legacy-only state. Rollback leaves the canonical row usable and does not
attempt to restore the obsolete key.

## Open Questions

None.
