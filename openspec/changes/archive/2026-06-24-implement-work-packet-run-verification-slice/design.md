## Context

Office Graph has accepted product contracts for work packets, work runs,
execution observations, and verification evidence. The current backend already
contains skeletal `OfficeGraph.WorkPackets`, `OfficeGraph.Runs`, and
`OfficeGraph.Verification` boundaries plus walking-skeleton tables for
`work_packets`, `runs`, `run_events`, evidence, checks, and verification
results. Those records prove the first manual-intake loop, but they do not yet
model versioned packet contracts, distinct work runs, non-agent child
activity, evidence candidates, or an API surface that product clients can use
as the next vertical slice.

This change implements the first execution spine: create a packet version,
start a work run from that packet, record at least one non-agent execution
observation, accept evidence for a required check, and record a verification
result that keeps the run unverified until explicit checks are satisfied.

## Goals / Non-Goals

**Goals:**

- Add typed persistence and Ash resources for versioned packet contracts,
  work runs, execution observations, evidence candidates, accepted evidence,
  and verification results.
- Expose a shared backend/API flow for creating and reading the packet-run-
  verification slice.
- Preserve operation correlation, authorization, graph identity, and typed
  source references for all meaningful state changes.
- Prove that work runs are parent execution records that can contain child
  activity other than agent executions.
- Keep the walking skeleton tests passing while adding product-slice tests.

**Non-Goals:**

- Do not implement the internal agent runtime or agent execution lifecycle.
- Do not implement provider webhooks, provider-native CI ingestion, or external
  writeback.
- Do not implement ordered placement, frontend UI, full work-packet
  projection rebuilding, approval gates, governed waivers, or broad realtime
  subscriptions.
- Do not continue expanding `proposed_graph_change` product language; this
  slice may interoperate with the existing code while using current structured
  change-proposal terminology in new artifacts.

## Decisions

1. **Implement around typed parent and child records.**

   Work runs SHALL be typed parent execution records. Child activity in this
   slice SHALL use `execution_observations` and typed links instead of
   treating `run_events.payload` as the product timeline. The existing
   `run_events` skeleton can remain for compatibility or be migrated, but new
   product behavior must not depend on generic event payloads for child
   semantics.

   Alternative considered: extend `run_events` with richer payloads. Rejected
   because the accepted design requires work runs to coordinate typed child
   records without collapsing ownership and lifecycle semantics.

2. **Add packet versions before broad packet compilation.**

   The first packet implementation SHALL create `work_packet_versions` with
   stable objective, context, requirements, success criteria, autonomy posture,
   source graph item references, and required check references. It SHALL NOT
   attempt full automatic context compilation. Initial commands can accept
   explicit typed references and documents.

   Alternative considered: keep a single `work_packets` row with mutable
   fields. Rejected because the accepted packet contract requires stable
   execution versions.

3. **Represent evidence candidates separately from accepted evidence.**

   The slice SHALL add an evidence-candidate record and an explicit acceptance
   path before creating or updating accepted evidence and verification results.
   Existing `evidence_items` can remain the accepted-evidence record family,
   but acceptance must preserve candidate, source, operation, and policy or
   actor basis.

   Alternative considered: mark all evidence submitted through the API as
   accepted immediately. Rejected because observations and agent/provider
   outputs must not satisfy verification by default.

4. **Use Ash-owned APIs first, with thin command exceptions only where needed.**

   Resource reads and simple creates SHALL use AshGraphql/AshJsonApi whenever
   practical. If an orchestration command spans WorkPackets, Runs, Verification,
   and Operations, the custom GraphQL/JSON entrypoint SHALL stay thin and call
   public context functions that own authorization, validation, and lifecycle
   behavior.

   Alternative considered: copy the manual walking-skeleton controller/schema
   pattern. Rejected because accepted API direction quarantines that code as a
   temporary smoke-test surface.

5. **Keep operation correlation mandatory for meaningful commands.**

   Packet creation, run start, observation recording, evidence acceptance, and
   verification result creation SHALL all link to operation correlation. This
   lets future audit, revisions, approval gates, agent executions, and provider
   observations attach to the same execution spine without duplicating payloads.

## Risks / Trade-offs

- **Risk: the slice becomes too broad.** Mitigation: implement only explicit
  human/manual or test-provider observations and leave provider adapters,
  agents, approval gates, waivers, and frontend views to later changes.
- **Risk: current skeleton table names conflict with durable product names.**
  Mitigation: use a forward-only migration to either rename skeleton tables or
  introduce product-named tables, then update Ash resources and tests in the
  same change. Do not edit historical migrations.
- **Risk: generated Ash APIs do not cover the orchestration command shape.**
  Mitigation: use generated APIs for resources and a thin custom command
  endpoint only for the multi-domain packet-run-verification flow.
- **Risk: evidence acceptance bypasses authorization.** Mitigation: require
  public context commands to receive session and operation context, enforce
  capability checks, and test denied actors.

## Migration Plan

1. Add a forward Ecto migration for packet versions, packet source/check join
   tables, work-run fields, execution observations, observation links, evidence
   candidates, and accepted-evidence acceptance metadata.
2. Update Ash resources and domains for WorkPackets, Runs, WorkGraph, and
   Verification.
3. Add or update public context functions and API entrypoints.
4. Backfill or safely migrate the local skeleton `runs`/`run_events` records
   if needed. This project has no production data dependency yet, but the
   migration should still be forward-only.
5. Run database setup/migration, domain tests, API smoke tests, Boundary,
   compile, format, and OpenSpec validation.

## Open Questions

- None for this slice. Provider-specific observation payloads, agent execution
  records, approval gates, waivers, frontend projection details, and ordered
  placement remain explicit future changes.
