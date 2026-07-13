## Why

Office Graph can model and read the manual-intake-to-verification workflow, but
operators cannot execute that workflow through supported product commands. The
only GraphQL write is a one-shot internal proving command, while the React
routes remain read-only beyond readiness validation.

## What Changes

- Add narrow GraphQL and JSON API commands for manual intake, proposed-change
  application, packet creation and versioning, run start, observation
  recording, evidence candidate creation and acceptance, and verification
  waiver.
- Add Relay mutations and route-owned forms/actions so operators can advance
  the current workflow without seeds, direct Elixir calls, or database edits.
- Preserve command affordances, authorization, operation correlation,
  idempotency, stale-command conflicts, and field-specific safe errors at every
  step.
- Capture operator clarification in versioned packet objective, context,
  requirements, success criteria, autonomy posture, sources, and required
  checks; defer a generic question queue and decision-record subsystem.
- **BREAKING** Remove the unreleased `executePacketRunVerification` one-shot
  mutation after the supported command sequence covers its current behavior and
  tests.

## Capabilities

### New Capabilities

- `operator-command-loop`: Defines the supported operator command sequence,
  step-specific results, stale-command handling, and end-to-end completion
  behavior.

### Modified Capabilities

- `manual-intake-adapter`: Expose authorized, replay-safe manual intake through
  supported product APIs.
- `change-proposal-application`: Expose proposal application as a narrow
  authorized command with stable conflict behavior.
- `work-packet-contracts`: Add explicit packet version creation after the
  initial packet and preserve current-version traceability.
- `work-runs`: Expose packet-backed run start through supported product APIs.
- `execution-observations`: Expose run observation recording through supported
  product APIs.
- `verification-evidence`: Expose evidence candidate creation, acceptance, and
  governed verification waiver as separate commands.
- `ash-api-surface`: Replace the one-shot custom mutation with thin transport
  modules over named domain commands.
- `operator-console`: Add mutation-driven actions and safe command feedback to
  the inbox-to-verification workflow.
- `packet-workspace`: Add packet creation, version editing, and run-start
  actions to the dedicated packet route.

## Impact

- Adds or changes Ash actions and public domain functions in Integrations,
  ProposedChanges, WorkPackets, Runs, and Verification.
- Adds custom Absinthe command types/resolvers and equivalent JSON API command
  routes where the dual-API contract requires them.
- Adds Relay mutation documents, generated artifacts, route-owned forms,
  pending/error/conflict states, and store refresh behavior under
  `assets/app/routes/operator/` and `assets/app/routes/packets/`.
- Adds a packet-version operation reference and verification-waiver persistence
  migration if the existing tables cannot preserve the required provenance.
- Removes the unreleased packet-run-verification compatibility mutation and its
  transport-only input/result types after replacement coverage passes.
