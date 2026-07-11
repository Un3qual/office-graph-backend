## 1. Command Foundation

- [x] 1.1 Add focused tests and shared command helpers that start server-owned operation correlations, record normalized input digests, and return stable idempotency and stale-state conflicts.
- [x] 1.2 Extend owner bootstrap and authorization policy coverage with the separate `verification.waive` capability and operation action.

## 2. Packet Versions And Verification Waivers

- [x] 2.1 Add failing packet tests, then implement concurrency-safe `WorkPackets.create_version/4` with expected-current-version checks, immutable version numbers, ordered bulk links, and operation replay validation.
- [x] 2.2 Add the nullable verification-result evidence migration and resource validation that distinguishes evidence-backed passed/failed results from evidence-free waived results.
- [x] 2.3 Add failing waiver tests, then implement `Verification.waive_required_check/5` with run/check locking, separate authorization, stale-state checks, audit/revision provenance, and aggregate run verification updates.

## 3. Step-Specific GraphQL Commands

- [x] 3.1 Add GraphQL tests and thin mutations for manual intake submission and complete proposed-change application.
- [x] 3.2 Add GraphQL tests and thin mutations for packet creation, packet version creation, and packet-backed run start.
- [x] 3.3 Add GraphQL tests and thin mutations for observation recording, evidence candidate creation, evidence acceptance, and verification waiver.
- [x] 3.4 Regenerate the GraphQL schema and add architecture coverage proving command resolvers remain transport-only and expose safe validation, authorization, idempotency, and conflict errors.

## 4. Step-Specific JSON Commands

- [x] 4.1 Add JSON API tests, request parsers, controllers, serializers, and routes for manual intake and proposal application.
- [ ] 4.2 Add JSON API tests and thin commands for packet creation/versioning and run start.
- [ ] 4.3 Add JSON API tests and thin commands for observations, evidence creation/acceptance, and waiver, including parity assertions with GraphQL behavior.

## 5. Relay Mutation Foundation

- [ ] 5.1 Add generated Relay mutation documents and route-owned mutation helpers for every step-specific command, with pending, safe error, field error, conflict, and success result mapping.
- [ ] 5.2 Add frontend tests and a shallow generic form-feedback primitive that remains free of product vocabulary and transport details.

## 6. Operator Console Actions

- [ ] 6.1 Add failing operator tests and a manual-intake form that submits through Relay, prevents duplicate pending submission, and refreshes the inbox.
- [ ] 6.2 Add failing operator tests and proposal-apply plus packet-create actions driven only by enabled command affordances and current selected-item defaults.
- [ ] 6.3 Add failing operator tests and run-start, observation, evidence candidate, evidence acceptance, and waiver actions that preserve still-valid workspace context on pending, validation, conflict, or authorization failure.

## 7. Packet Workspace Actions

- [ ] 7.1 Add failing packet-route tests and packet creation/version forms with expected-current-version conflicts, immutable version history display, and authoritative refetch after mutation.
- [ ] 7.2 Add failing packet-route tests and run-start action gated by current readiness and command affordance, linking the returned run state without adding global client workflow state.

## 8. Retire The One-Shot Workflow Path

- [ ] 8.1 Migrate packet-run-verification domain and API behavior tests to the separate command sequence, then remove the one-shot GraphQL mutation, transport input/result modules, schema imports, and `OfficeGraph.PacketRunVerification` coordinator.
- [ ] 8.2 Run a caller audit proving no current source, test, generated schema, Relay artifact, or durable spec references the removed one-shot product path.

## 9. Change Verification

- [ ] 9.1 Run focused backend, GraphQL, JSON, authorization, migration, Relay, route, and production-build checks; then run strict OpenSpec validation, `mix verify`, and `git diff --check`.
- [ ] 9.2 Synchronize all delta requirements into durable specs, archive `complete-operator-command-loop`, confirm no unintended active-change or compatibility references remain, and publish the stacked PR against `codex/close-completed-changes`.
