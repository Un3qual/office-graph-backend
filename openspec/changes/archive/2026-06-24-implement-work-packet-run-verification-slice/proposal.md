## Why

The accepted design now defines work packets, work runs, execution
observations, and verification evidence, but the backend only has skeletal
records from the walking skeleton. The next useful product slice is a thin
end-to-end execution spine that can create a packet, start a work run, attach
non-agent execution activity, record evidence, and expose the result through
the shared backend/API path.

## What Changes

- Evolve the existing skeletal work-packet, run, run-event, evidence, and
  verification records into the first usable backend slice for packet-backed
  execution.
- Add the minimum relational/Ash resources, domain actions, and migrations
  needed for versioned packet contracts, work-run lifecycle, execution
  observations, evidence candidates, accepted evidence, and verification
  results.
- Expose the slice through shared Ash-owned GraphQL and JSON API surfaces or
  thin command entrypoints that call the same public context actions.
- Add tests proving packet creation, work-run start, child observation linkage,
  evidence acceptance, verification result recording, authorization behavior,
  operation correlation, and API parity.
- Keep agent runtime execution, provider integrations, frontend UI, ordered
  placement, broad projections, waivers, and approval-gate workflows out of
  this slice unless a narrow stub is required for linkage.

## Capabilities

### New Capabilities

- None. This implements the first vertical slice across existing accepted
  product capabilities.

### Modified Capabilities

- `work-packet-contracts`: add requirements for the initial persisted
  packet/version contract and packet creation command.
- `work-runs`: add requirements for initial work-run creation, lifecycle,
  child linkage, and aggregate status behavior.
- `execution-observations`: add requirements for initial human/provider
  observation records that can link to work runs and verification.
- `verification-evidence`: add requirements for initial evidence candidates,
  accepted evidence, and verification result recording.
- `work-packet-projections`: add requirements for the first authorized packet
  and run summary projection returned by backend/API reads.
- `ash-api-surface`: add requirements for exposing this slice through
  Ash-backed GraphQL and JSON API surfaces or documented thin command
  exceptions.

## Impact

- Affected code: `lib/office_graph/work_packets/`, `lib/office_graph/runs/`,
  `lib/office_graph/verification.ex`, `lib/office_graph/work_graph/`,
  `lib/office_graph_web/`, migrations, seeds/fixtures, and tests.
- Affected APIs: GraphQL and JSON API endpoints or generated Ash APIs for the
  packet-run-verification flow.
- Affected data model: work packet versions, work runs, execution
  observations, evidence candidates/acceptance, verification results, and
  operation-correlation references.
- Verification: OpenSpec validation, compile, format, boundary checks,
  migration/database tests, domain tests, API smoke tests, and diff hygiene.
