## 1. Baseline And Scope Guard

- [ ] 1.1 Re-read the accepted specs for `work-packet-contracts`,
  `work-runs`, `execution-observations`, `verification-evidence`,
  `work-packet-projections`, and `ash-api-surface`.
- [ ] 1.2 Confirm the existing walking-skeleton tests and API smoke tests pass
  before changing packet, run, or verification behavior.
- [ ] 1.3 Confirm this change does not implement agent runtime execution,
  provider webhooks, ordered placement, frontend UI, approval gates, waivers,
  or broad realtime subscriptions.

## 2. Persistence And Migration

- [ ] 2.1 Add a forward migration for packet versions, packet source
  references, and packet required-check references without editing historical
  migrations.
- [ ] 2.2 Add or migrate work-run persistence so work runs record packet
  version, objective, initiator or trigger, authority posture, aggregate
  state, operation correlation, and timestamps.
- [ ] 2.3 Add execution observation persistence with source identity, observed
  status, normalized status, source time, ingestion time, freshness, trust
  basis, operation correlation, idempotency basis, and typed links.
- [ ] 2.4 Add evidence-candidate persistence with source, target check or
  claim, related work run, observation or artifact references, freshness,
  trust basis, sensitivity, operation correlation, and candidate state.
- [ ] 2.5 Add accepted-evidence metadata needed to link accepted evidence to
  the candidate, acceptance actor or policy basis, acceptance operation,
  related work run, and visibility constraints.
- [ ] 2.6 Add required indexes, uniqueness constraints, foreign keys, and
  scope-safe constraints for packet versions, work runs, observations,
  evidence candidates, and verification results.
- [ ] 2.7 Run database create/migrate/reset or equivalent test-database setup
  through the Nix shell and Docker Compose Postgres path.

## 3. Ash Resources And Boundaries

- [ ] 3.1 Add or update WorkPackets Ash resources for work packets, packet
  versions, packet source references, and packet required-check references.
- [ ] 3.2 Add or update Runs Ash resources for work runs and typed observation
  links without relying on opaque run-event payloads for product semantics.
- [ ] 3.3 Add or update WorkGraph/Verification Ash resources for execution
  observations, evidence candidates, accepted-evidence metadata, and
  verification-result run linkage.
- [ ] 3.4 Register new resources in their owning Ash domains and keep public
  context boundary exports/dependencies explicit.
- [ ] 3.5 Add authorization policies and capability checks for packet creation,
  run start, observation recording, evidence candidate creation, evidence
  acceptance, verification result recording, and summary reads.

## 4. Domain Commands And Lifecycle

- [ ] 4.1 Implement a public WorkPackets command that creates a packet and
  first packet version with operation correlation and typed source/check
  references.
- [ ] 4.2 Implement packet readiness validation for objective, success
  criteria, required checks, source references, allowed autonomy posture, and
  authorization.
- [ ] 4.3 Implement a public Runs command that starts a work run from a ready
  packet version and rejects draft, stale, superseded, unauthorized, or missing
  packet versions.
- [ ] 4.4 Implement observation recording with source/idempotency handling and
  typed work-run linkage.
- [ ] 4.5 Implement evidence candidate creation from observations, work runs,
  artifacts, or human notes without accepting evidence by default.
- [ ] 4.6 Implement evidence acceptance and verification-result recording with
  authorization, scope validation, operation correlation, and missing-evidence
  reasons.
- [ ] 4.7 Implement aggregate work-run status calculation that separates child
  execution state from verification state.

## 5. API And Projection Surface

- [ ] 5.1 Expose resource reads and simple mutations through AshGraphql and
  AshJsonApi where they map cleanly to resource actions.
- [ ] 5.2 Add thin GraphQL and JSON command entrypoints only where orchestration
  spans WorkPackets, Runs, Verification, and Operations.
- [ ] 5.3 Ensure GraphQL and JSON command entrypoints share the same public
  context actions, authorization semantics, validation errors, and operation
  correlation.
- [ ] 5.4 Add an authorized packet-run summary projection that distinguishes
  packet contract, work-run state, child observations, accepted evidence,
  verification result, and missing evidence reasons.
- [ ] 5.5 Keep existing walking-skeleton endpoints isolated and avoid copying
  their manual transport pattern for new product resource surfaces.

## 6. Tests

- [ ] 6.1 Add domain tests for packet creation and stable packet-version
  references.
- [ ] 6.2 Add domain tests for rejecting work-run start from draft,
  not-ready, stale, missing, cross-scope, or unauthorized packet versions.
- [ ] 6.3 Add domain tests for recording child execution observations and
  preserving typed child references.
- [ ] 6.4 Add domain tests proving successful child observations do not mark a
  work run verified without accepted evidence and verification results.
- [ ] 6.5 Add verification tests for evidence candidate creation, acceptance,
  authorization rejection, cross-scope rejection, and result recording.
- [ ] 6.6 Add API smoke tests proving GraphQL and JSON API parity for the
  packet-run-verification flow.
- [ ] 6.7 Update or add boundary and architecture conformance tests for any new
  public context dependencies or generated API modules.
- [ ] 6.8 Keep existing walking-skeleton tests passing.

## 7. Verification

- [ ] 7.1 Run `mix format --check-formatted` from the project Nix shell.
- [ ] 7.2 Run `mix compile --warnings-as-errors` from the project Nix shell.
- [ ] 7.3 Run `mix test` from the project Nix shell with Docker Compose
  Postgres available.
- [ ] 7.4 Run `mix boundary.check` from the project Nix shell.
- [ ] 7.5 Run `openspec validate implement-work-packet-run-verification-slice
  --strict`.
- [ ] 7.6 Run `openspec validate --changes --strict`.
- [ ] 7.7 Run `git diff --check`.
