# Operator Command Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let operators execute the manual-intake-to-verification workflow through step-specific GraphQL, JSON, and Relay product commands.

**Architecture:** Keep every write in its owning domain and use `OfficeGraph.Operations` for server-owned operation correlation and replay digests. Add immutable packet versions and evidence-free governed waivers, expose thin dual-API transports, then add route-owned Relay mutations without creating another client workflow store.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix 1.8, Ash 3.29, Postgres, Absinthe, AshJsonApi, React 19, Relay 21, React Router 8, TypeScript 5.9, Vitest, OpenSpec 1.4.1.

## Global Constraints

- Enter project tools through `nix --extra-experimental-features 'nix-command flakes' develop --command`.
- Use test-driven development: add one failing behavior test, confirm the expected failure, implement the minimum behavior, and rerun the focused test.
- Keep Tailwind, LiveView product UI, TanStack Query, and generic command-bus abstractions out of the change.
- Keep server state in Relay and transient form state in route-local React state.
- Start operations server-side; clients never supply actor, tenant, session, capability, or operation ids.
- Preserve authorization, operation correlation, idempotency, transaction, audit, revision, ordered-collection, and bounded-query contracts.
- Commit each independently testable task before beginning the next task.
- This branch targets `codex/close-completed-changes` while stacked.

---

### Task 1: Command Operation And Authorization Foundation

**Files:**
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph/authorization.ex`
- Test: `test/office_graph/operations_test.exs`
- Test: `test/office_graph/foundation/bootstrap_test.exs`

**Interfaces:**
- Consumes: `Operations.start_operation/3`, `Identity.SessionContext`, owner bootstrap.
- Produces: `Operations.start_command/4`, `Operations.validate_command_replay/2`, actions `:work_packet_version_create` and `:verification_waive`, capability `verification.waive`.

- [x] **Step 1: Add failing operation digest tests**

Add tests that start a command twice with the same key/input and once with changed input:

```elixir
assert {:ok, first} =
         Operations.start_command(session, :work_packet_version_create, "version-1", %{
           packet_id: packet_id,
           source_graph_item_ids: [source_id]
         })

assert {:ok, replay} =
         Operations.start_command(session, :work_packet_version_create, "version-1", %{
           packet_id: packet_id,
           source_graph_item_ids: [source_id]
         })

assert replay.id == first.id

assert {:error, {:command_idempotency_conflict, operation_id}} =
         Operations.start_command(session, :work_packet_version_create, "version-1", %{
           packet_id: packet_id,
           source_graph_item_ids: [other_source_id]
         })
```

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/operations_test.exs
```

Expected: failure because `start_command/4` is undefined.

- [x] **Step 2: Implement deterministic command digests**

Add these public signatures:

```elixir
def start_command(session_context, action, idempotency_key, input)
def validate_command_replay(operation, input)
```

Normalize maps by sorted string keys, preserve list order, hash
`:erlang.term_to_binary(normalized_input)` with SHA-256, and store the hex digest
as `metadata["command_input_digest"]`. On an existing operation, return
`{:error, {:command_idempotency_conflict, operation.id}}` unless the digest
matches.

- [x] **Step 3: Add waiver capability tests and implementation**

Extend bootstrap assertions to include `"verification.waive"`. Add:

```elixir
@actions %{
  work_packet_version_create: "work_packet.version.create",
  verification_waive: "verification.waive"
}
```

to Operations and matching owner capability atoms/strings to Authorization.
Run the two focused test files and confirm they pass.

- [x] **Step 4: Commit the foundation**

```bash
git add lib/office_graph/operations.ex lib/office_graph/authorization.ex test/office_graph/operations_test.exs test/office_graph/foundation/bootstrap_test.exs
git commit -m "feat: add operator command operations"
```

### Task 2: Immutable Packet Version Commands

**Files:**
- Create: `priv/repo/migrations/20260711000500_add_packet_version_titles.exs`
- Modify: `lib/office_graph/work_packets.ex`
- Modify: `lib/office_graph/work_packets/work_packet.ex`
- Modify: `lib/office_graph/work_packets/work_packet_version.ex`
- Modify: `lib/office_graph/work_packets/changes/validate_current_version.ex`
- Test: `test/office_graph/work_packets/work_packet_run_verification_test.exs`

**Interfaces:**
- Consumes: `Operations.start_command/4`, packet/readiness bulk helpers.
- Produces: `WorkPackets.create_version/4` returning `{:ok, %{packet: packet, version: version, source_references: list, required_checks: list}}`.

- [x] **Step 1: Add failing packet-version tests**

Cover success, sequential version numbers, title preservation, current-version
update, reordered-input replay conflict, and stale expected version:

```elixir
assert {:ok, result} =
         WorkPackets.create_version(session, operation, packet, %{
           expected_current_version_id: packet.current_version_id,
           title: "Revised packet",
           objective: "Revised objective",
           context_summary: "Current context",
           requirements: "Current requirements",
           success_criteria: "Current success criteria",
           autonomy_posture: "human_supervised",
           source_graph_item_ids: [source.id],
           verification_check_ids: [check.id]
         })

assert result.version.version_number == 2
assert result.version.title == "Revised packet"
assert result.packet.current_version_id == result.version.id
```

Expected RED: `create_version/4` is undefined and version has no title.

- [x] **Step 2: Add the version title migration and resource attribute**

Generate the migration through the Nix shell, then make it:

```elixir
alter table(:work_packet_versions) do
  add :title, :text
end

execute """
UPDATE work_packet_versions AS versions
SET title = packets.title
FROM work_packets AS packets
WHERE versions.work_packet_id = packets.id
"""

alter table(:work_packet_versions) do
  modify :title, :text, null: false
end
```

The down migration removes `title`. Add the non-null public `:title` attribute
and accept it in the private create action. Pass packet title when creating
version 1.

- [x] **Step 3: Implement `create_version/4`**

Lock the operation and packet inside `Repo.transaction/1`; validate action,
session, scope, expected current version, unique ordered ids, required check
state, and source/check pairing. Set `version_number` to the locked packet's
current version plus one, bulk-create links with positions, then call a private
packet update that sets `current_version_id`, `title`, and derived state.

Return `{:error, {:stale_packet_version, packet.id, actual_version_id}}` on an
expected-version mismatch. Replay by `work_packet_versions.operation_id` and
compare every scalar plus ordered link ids.

- [x] **Step 4: Run focused packet and migration tests**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix ecto.migrate
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_packets/work_packet_run_verification_test.exs
```

Expected: all packet/run contract tests pass.

- [x] **Step 5: Commit packet versioning**

```bash
git add priv/repo/migrations lib/office_graph/work_packets.ex lib/office_graph/work_packets test/office_graph/work_packets/work_packet_run_verification_test.exs
git commit -m "feat: add immutable packet versions"
```

### Task 3: Governed Verification Waivers

**Files:**
- Create: `priv/repo/migrations/20260711001000_allow_waived_verification_results.exs`
- Modify: `lib/office_graph/verification.ex`
- Modify: `lib/office_graph/work_graph/verification_result.ex`
- Create: `lib/office_graph/work_graph/verification_result/validate_result_evidence.ex`
- Modify: `lib/office_graph/runs/run_required_check.ex`
- Modify: `lib/office_graph/runs.ex`
- Test: `test/office_graph/work_packets/work_packet_run_verification_test.exs`
- Test: `test/office_graph/work_graph/ash_authorization_test.exs`

**Interfaces:**
- Consumes: `Operations.start_command/4`, run locking and verification recomputation.
- Produces: `Verification.waive_required_check/5` and private `RunRequiredCheck.mark_waived` action.

- [x] **Step 1: Add failing waiver and authorization tests**

Cover successful waiver, missing capability, stale run state, wrong check, an
already satisfied check, idempotent replay, changed reason conflict, multi-check
runs, and audit/revision records. Assert:

```elixir
assert {:ok, waived} =
         Verification.waive_required_check(session, operation, run, required_check, %{
           expected_execution_state: run.execution_state,
           expected_verification_state: run.verification_state,
           reason: "Approved exception",
           policy_basis: "owner_exception"
         })

assert waived.verification_result.result == "waived"
assert waived.verification_result.evidence_item_id == nil
assert waived.required_check.state == "waived"
```

Expected RED: function/action and nullable evidence behavior do not exist.

- [x] **Step 2: Add waiver persistence rules**

Create a reversible migration that drops the evidence-item foreign-key null
constraint and restores it only after asserting no null rows in `down/0`.
Replace `ValidateEvidenceCheckMatch` on `VerificationResult.create` with
`ValidateResultEvidence`:

```elixir
"waived" -> require_nil_evidence(changeset)
result when result in ["passed", "failed"] -> require_matching_evidence(changeset)
_ -> Ash.Changeset.add_error(changeset, field: :result, message: "is invalid")
```

Add private `mark_waived` to `RunRequiredCheck`.

- [x] **Step 3: Implement the waiver transaction**

Add:

```elixir
def waive_required_check(session_context, operation, run, required_check, attrs)
```

Authorize `:verification_waive`, lock/reload run and required checks, compare
expected states, require pending membership, create a `VerificationResult` with
`result: "waived"`, nil evidence, actor/reason/policy/operation, mark the one
required check waived, call shared run verification recomputation, and record
audit/revision rows.

- [x] **Step 4: Run focused verification tests and commit**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_packets/work_packet_run_verification_test.exs test/office_graph/work_graph/ash_authorization_test.exs
git add priv/repo/migrations lib/office_graph/verification.ex lib/office_graph/work_graph/verification_result.ex lib/office_graph/work_graph/verification_result lib/office_graph/runs.ex lib/office_graph/runs/run_required_check.ex test/office_graph
git commit -m "feat: add governed verification waivers"
```

### Task 4: Step-Specific GraphQL Commands

**Files:**
- Create: `lib/office_graph_web/graphql/operator_commands/input.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/types.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/mutations.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/resolvers/intake.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/resolvers/packets.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/resolvers/runs.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/resolvers/verification.ex`
- Modify: `lib/office_graph_web/graphql/schema.ex`
- Modify: `lib/office_graph_web/graphql/common/errors.ex`
- Test: `test/office_graph_web/operator_commands_graphql_test.exs`
- Test: `test/office_graph/architecture/ash_conformance_test.exs`

**Interfaces:**
- Consumes: all step-specific domain functions from Tasks 1-3.
- Produces: GraphQL mutations `submitManualIntake`, `applyProposedChanges`, `createWorkPacket`, `createWorkPacketVersion`, `startWorkRun`, `recordExecutionObservation`, `createEvidenceCandidate`, `acceptEvidence`, `waiveVerificationCheck`.

- [ ] **Step 1: Add failing GraphQL command tests**

For every mutation, assert successful typed ids/operation id, same-key replay,
changed-input conflict, missing field, forbidden session, and transaction
rollback. Use one complete sequence test that passes each prior result into the
next mutation.

Run the test and confirm schema validation fails because the fields do not
exist.

- [ ] **Step 2: Implement shared input and result types**

`Input.parse/2` takes a command atom and args, trims/casts UUID fields, preserves
ordered UUID lists, requires nonblank strings, and never atomizes arbitrary
keys. Define command-specific input objects and payload objects; every payload
contains:

```elixir
field :command, non_null(:string)
field :operation_id, non_null(:id)
field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
```

plus its typed result records.

- [ ] **Step 3: Implement thin resolvers and schema imports**

Each resolver performs only: parse input -> resolve request session ->
`Operations.start_command/4` -> fetch named target -> call one owning domain
function -> map payload. Add architecture assertions that resolver source does
not call `Repo`, build Ash changesets, or call another resolver.

- [ ] **Step 4: Add safe conflict mappings and verify GraphQL**

Map `command_idempotency_conflict`, `stale_packet_version`, and stale run states
to stable Absinthe extensions. Run focused tests, schema generation check, and
architecture tests. Commit as:

```bash
git add lib/office_graph_web/graphql lib/office_graph_web/graphql/schema.ex test/office_graph_web/operator_commands_graphql_test.exs test/office_graph/architecture/ash_conformance_test.exs assets/schema.graphql
git commit -m "feat: expose operator GraphQL commands"
```

### Task 5: Step-Specific JSON Commands

**Files:**
- Create: `lib/office_graph_web/json_api/operator_commands/input.ex`
- Create: `lib/office_graph_web/json_api/operator_commands/controller.ex`
- Create: `lib/office_graph_web/json_api/operator_commands/serializer.ex`
- Modify: `lib/office_graph_web/router.ex`
- Modify: `lib/office_graph_web/request_session.ex`
- Modify: `lib/office_graph_web/json_api/common/errors.ex`
- Test: `test/office_graph_web/operator_commands_json_test.exs`
- Test: `test/office_graph/architecture/ash_conformance_test.exs`

**Interfaces:**
- Consumes: Task 4 command input field contracts and Tasks 1-3 domain functions.
- Produces: POST routes under `/api/v1/commands/<kebab-command>` with JSON payloads equivalent to GraphQL semantics.

- [ ] **Step 1: Add failing JSON command parity tests**

Exercise the same complete sequence and failure matrix as GraphQL. Assert JSON
responses use `{data: %{command, operation_id, affected_ids, result}}` and
`{error: %{code, detail, field?}}`, with HTTP 409 for replay/stale conflicts,
403 for forbidden, and 422 for validation.

- [ ] **Step 2: Resolve request sessions from Plug connections**

Add `RequestSession.resolve_conn/1`, using the actor assigned by
`LocalApiOwnerPlug` and the same local bootstrap fallback as GraphQL. Do not
accept session ids from JSON input.

- [ ] **Step 3: Implement explicit command routes and thin controller**

Register the command scope before the generated `/api/v1` forward so it cannot
be swallowed by the AshJsonApi router. Controller actions use the same
parse/start-operation/domain-call order as GraphQL. Serializer maps only typed
results and ids.

- [ ] **Step 4: Verify parity and commit**

Run JSON, GraphQL, and architecture tests together. Commit:

```bash
git add lib/office_graph_web/json_api lib/office_graph_web/router.ex lib/office_graph_web/request_session.ex test/office_graph_web/operator_commands_json_test.exs test/office_graph/architecture/ash_conformance_test.exs
git commit -m "feat: expose operator JSON commands"
```

### Task 6: Relay Mutation And Form Feedback Foundation

**Files:**
- Create: `assets/app/relay/commandMutation.ts`
- Create: `assets/app/relay/commandMutation.test.tsx`
- Create: `assets/app/routes/operator/commands.ts`
- Create: `assets/app/routes/operator/commandWorkflow.ts`
- Create: `assets/app/routes/operator/commandWorkflow.test.tsx`
- Create: `assets/app/routes/packets/commands.ts`
- Create: `assets/app/routes/packets/commandWorkflow.ts`
- Create: `assets/app/routes/packets/commandWorkflow.test.tsx`
- Create: `assets/src/ui/FormFeedback.tsx`
- Modify: `assets/src/ui/primitives.test.tsx`
- Modify: `assets/src/ui/importBoundaries.test.ts`

**Interfaces:**
- Consumes: Task 4 GraphQL mutations.
- Produces: generated mutation artifacts, route-owned `useOperatorCommand` and `usePacketCommand` hooks, generic `FormFeedback`.

- [ ] **Step 1: Add failing pure workflow and primitive tests**

Test result mapping for success, field errors, conflict, forbidden, and unknown
safe failure. Test that `FormFeedback` renders caller copy and field messages
without importing Relay or product vocabulary.

- [ ] **Step 2: Add Relay mutation documents and compile them**

Define one exported `graphql` document per command in the owning route. Request
`command`, `operationId`, `affectedIds`, and minimal typed result fields. Run
`pnpm run relay` and commit generated artifacts with the source documents.

- [ ] **Step 3: Implement route-owned mutation hooks**

Wrap Relay `commitMutation` in a shared transport-only lifecycle helper, then
expose route-owned hooks for each command with a discriminated state:

```typescript
type CommandState =
  | { status: "idle" }
  | { status: "pending" }
  | { status: "field-error"; fields: ReadonlyArray<FieldError> }
  | { status: "conflict"; message: string }
  | { status: "error"; message: string }
  | { status: "success"; operationId: string; affectedIds: ReadonlyArray<string> };
```

Expose `submit(input)`, `state`, and `reset()`. The hook does not own route
selection or durable records. The shared helper may normalize Relay transport
errors, but it MUST NOT name product commands, select route queries, or retain
workflow state.

- [ ] **Step 4: Verify frontend foundation and commit**

```bash
cd assets
pnpm run relay:check
pnpm exec vitest run src/ui/primitives.test.tsx src/ui/importBoundaries.test.ts app/relay/commandMutation.test.tsx app/routes/operator/commandWorkflow.test.tsx app/routes/packets/commandWorkflow.test.tsx
pnpm run typecheck
git add app src
git commit -m "feat: add Relay command foundation"
```

### Task 7: Operator Console Command Actions

**Files:**
- Create: `assets/app/routes/operator/components/ManualIntakeForm.tsx`
- Create: `assets/app/routes/operator/components/PacketCommandForm.tsx`
- Create: `assets/app/routes/operator/components/RunCommandForm.tsx`
- Create: `assets/app/routes/operator/components/EvidenceCommandForm.tsx`
- Modify: `assets/app/routes/operator/OperatorWorkspace.tsx`
- Modify: `assets/app/routes/operator/OperatorInspector.tsx`
- Modify: `assets/app/routes/operator/workflow.ts`
- Modify: `assets/app/routes/operator/route.tsx`
- Modify: `assets/app/routes/operator/route.test.tsx`
- Modify: `assets/app/styles/global.css`

**Interfaces:**
- Consumes: Task 6 command hooks and existing command affordances.
- Produces: manual intake, proposal apply, packet create, run start, observation, candidate, acceptance, and waiver UI.

- [ ] **Step 1: Add failing manual intake and proposal tests**

Assert forms appear only for allowed contexts, submit exact mutation variables,
disable while pending, show safe errors, and refetch the inbox on success.

- [ ] **Step 2: Implement intake and proposal actions**

Use controlled route-local fields. Generate idempotency keys once per explicit
submission attempt and retain them only for retry of the same normalized input.
After success, refetch `OperatorWorkflowRouteQuery` with current page variables.

- [ ] **Step 3: Add failing packet/run/evidence/waiver tests**

Cover enabled/disabled/hidden affordances, defaults, sequential results,
selection preservation during pending state, field errors, stale conflicts,
authorization failures, and run-state refetch.

- [ ] **Step 4: Implement inspector command forms**

Keep each form in the panel that owns its state. Do not render an action unless
the matching affordance state is `enabled`. Pass Relay ids/current states as
concurrency input, and refetch only the affected readiness or run query.

- [ ] **Step 5: Verify and commit operator actions**

Run operator route tests, command workflow tests, import boundaries, and
typecheck. Commit:

```bash
git add assets/app/routes/operator assets/app/styles/global.css
git commit -m "feat: add operator workflow actions"
```

### Task 8: Packet Workspace Commands

**Files:**
- Create: `assets/app/routes/packets/components/PacketEditor.tsx`
- Create: `assets/app/routes/packets/components/PacketRunForm.tsx`
- Modify: `assets/app/routes/packets/PacketWorkspace.tsx`
- Modify: `assets/app/routes/packets/data.ts`
- Modify: `assets/app/routes/packets/types.ts`
- Modify: `assets/app/routes/packets/workflow.ts`
- Modify: `assets/app/routes/packets/route.tsx`
- Modify: `assets/app/routes/packets/route.test.tsx`
- Modify: `assets/app/styles/global.css`

**Interfaces:**
- Consumes: Task 6 packet command hook and packet Relay query.
- Produces: packet creation, immutable version editor, version history, and run-start UI.

- [ ] **Step 1: Expand the packet query through failing tests**

Require current-version contract fields, ordered sources/checks, versions, and
run-start affordance. Verify Relay compiler failure before updating the query
and generated artifacts.

- [ ] **Step 2: Add packet create/version tests and UI**

Cover initial values, exact expected current-version id, immutable history,
pending state, stale conflict/refetch, changed selection, and successful current
version display.

- [ ] **Step 3: Add run-start tests and UI**

Render only when current readiness/affordance permits. Submit source surface,
reason, and authority posture; show returned run link/state and refetch packet
data without a global client store.

- [ ] **Step 4: Verify and commit packet actions**

Run packet tests, Relay check, typecheck, import boundaries, and production
build. Commit:

```bash
git add assets/app/routes/packets assets/app/styles/global.css assets/app/relay/__generated__
git commit -m "feat: add packet workspace actions"
```

### Task 9: Retire One-Shot Mutation And Complete The Change

**Files:**
- Delete: `lib/office_graph/packet_run_verification.ex`
- Delete: `lib/office_graph_web/graphql/packet_run_verification/`
- Delete: `test/office_graph/packet_run_verification_test.exs`
- Delete: `test/office_graph_web/packet_run_verification_api_test.exs`
- Delete: `test/office_graph_web/packet_run_verification_input_test.exs`
- Modify: `lib/office_graph_web/graphql/schema.ex`
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`
- Modify: `openspec/changes/complete-operator-command-loop/tasks.md`
- Modify: `docs/superpowers/plans/README.md`

**Interfaces:**
- Consumes: replacement domain/API/UI coverage from Tasks 1-8.
- Produces: no current one-shot caller, complete/verified OpenSpec change, stacked PR.

- [ ] **Step 1: Move remaining behavior coverage before deletion**

Compare every one-shot domain/API/input test with the step-specific suites.
Move any unique readiness, source-check mismatch, evidence-result, trimming, or
transaction assertion into the relevant command test and run it red/green.

- [ ] **Step 2: Delete the one-shot path and audit callers**

Remove schema imports, modules, and tests. Run:

```bash
rg -n "PacketRunVerification|execute_packet_run_verification|executePacketRunVerification|packet-run-verification" lib assets test openspec/specs openspec/project.md
```

Expected: no current product/source/spec matches.

- [ ] **Step 3: Run complete verification**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate complete-operator-command-loop --strict
nix --extra-experimental-features 'nix-command flakes' develop --command mix verify
git diff --check
```

Expected: strict change validation and the complete backend/frontend gate pass.

- [ ] **Step 4: Complete artifacts and publish**

Mark every OpenSpec task complete, sync all ten delta specs into durable specs,
archive the change, archive this plan, commit completion, push
`codex/operator-command-loop`, and create a draft PR targeting
`codex/close-completed-changes` with explicit stack dependency and verification
evidence.
