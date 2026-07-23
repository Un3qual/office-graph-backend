# OpenSpec Product-Boundary Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove OpenSpec from Office Graph product/runtime semantics and replace
the invalid canonical `openspec-review` definition with a tool-free,
product-native `run-review` agent.

**Architecture:** Preserve the existing governed, run-linked AgentRuntime and
its single deterministic model-review step. Correct the canonical definition,
binding command, operator projection, migrations, tests, and active OpenSpec
artifacts in place. OpenSpec remains only in repository-local planning,
development tooling, and verification.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix, Ash, Ecto/Postgres, Oban,
ExUnit, OpenSpec 1.4.1, Nix.

## Global Constraints

- OpenSpec is only the workflow for building Office Graph. Office Graph product
  features are not inherently OpenSpec features.
- Production Office Graph code must not invoke OpenSpec, read `openspec/`
  artifacts, mount the Office Graph source checkout, or require the OpenSpec
  CLI.
- The canonical product agent key is exactly `run-review`.
- The canonical product agent uses the existing `deterministic` model adapter,
  has an empty tool allowlist, and requests exactly `agent.invoke`,
  `agent.model.generate`, `proposal.create`, and `evidence.suggest`.
- The binding command is exactly `bind_run_review_agent/2`.
- No alias, fallback, compatibility lookup, or runtime migration preserves
  `openspec-review`.
- Existing generic runtime, authority, approval, context-expansion,
  conversation, retry, audit, and provenance behavior remains unchanged.
- Initial outputs remain proposal-first and cannot directly mutate business
  state, perform external writes, or complete verification.
- Use the project Nix flake for every runtime, test, formatting, and OpenSpec
  command.
- Use behavior tests; do not add permanent source-string tests tied to file
  names or implementation layout.

---

### Task 1: Correct The Active OpenSpec Contract

**Files:**
- Modify: `openspec/changes/implement-internal-agent-runtime/proposal.md`
- Modify: `openspec/changes/implement-internal-agent-runtime/design.md`
- Modify: `openspec/changes/implement-internal-agent-runtime/tasks.md`
- Modify: `openspec/changes/implement-internal-agent-runtime/specs/agent-definitions/spec.md`
- Modify: `openspec/changes/implement-internal-agent-runtime/specs/agent-runtime/spec.md`
- Modify: `openspec/changes/implement-internal-agent-runtime/specs/agent-tool-adapters/spec.md`

**Interfaces:**
- Consumes: fixed product boundary in `openspec/project.md`.
- Produces: corrected acceptance contract for Tasks 2-4.

- [ ] **Step 1: Replace the proposal's OpenSpec product agent**

Replace the OpenSpec-specific bullet with:

```markdown
- Add the first automatic run-review agent using authorized Office Graph run,
  work-packet, graph, check, conversation, and evidence context without local
  repository or planning-tool access.
```

- [ ] **Step 2: Replace design goal and Decision 10**

The goal must say:

```markdown
- Deliver one deterministic product-native run-review agent and focused operator
  UI.
```

Decision 10 must define a migration-owned, tool-free `run-review` definition
that consumes the existing immutable context package and routes validated
outputs through existing proposal/evidence/conversation owners. It must
explicitly reject production dependencies on Git, the Office Graph checkout,
OpenSpec files, or the OpenSpec CLI.

Migration-plan step 5 must say:

```markdown
5. Install and bind the run-review agent and add the focused operator UI.
```

- [ ] **Step 3: Correct the definition and invocation delta specs**

In `agent-definitions/spec.md`, replace the installation scenario with:

```markdown
#### Scenario: Run review agent is installed
- **WHEN** the runtime migration runs
- **THEN** the canonical run-review definition MUST exist without an
  application seed, MUST have no tool allowlist, and MUST allow only its
  declared proposal-first outputs
```

In `agent-runtime/spec.md`, replace “Automatic OpenSpec review starts” with:

```markdown
#### Scenario: Automatic run review starts
- **WHEN** a declared system trigger requests the bound run-review agent for an
  authorized run and selected graph context
- **THEN** AgentRuntime MUST validate the generic system operation, definition
  binding, run, scope, and trigger authority before enqueueing execution
```

- [ ] **Step 4: Remove repository/OpenSpec runtime requirements**

Delete `Repository Tooling Is Release Configured And Ready` and its scenarios
from `agent-tool-adapters/spec.md`. The remaining adapter contract stays
provider-neutral.

- [ ] **Step 5: Correct completed task descriptions**

Rewrite Tasks 1.2, 1.3, and 7.1-7.3 without changing their checked state:

```markdown
- [x] 1.2 Add focused AgentRuntime and NodeConversations resources/domains/migrations, indexes, lifecycle constraints, ownership/API ledgers, and the migration-owned run-review definition.
- [x] 1.3 Add failing tests and implement the authorized organization-binding command for the run-review definition and backend agent principal.
- [x] 7.1 Add end-to-end deterministic tests for the run-review agent consuming authorized Office Graph context and producing messages, findings, proposals, checks, and evidence candidates.
- [x] 7.2 Implement the tool-free canonical run-review workflow over immutable context packages, proving it has no local repository, planning-tool, external-write, or direct-mutation path.
- [x] 7.3 Verify automatic run review through the existing durable model step, product-native operator affordances, and deterministic no-network acceptance coverage.
```

- [ ] **Step 6: Validate the corrected active change**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate implement-internal-agent-runtime --strict
```

Expected: `Change 'implement-internal-agent-runtime' is valid`.

- [ ] **Step 7: Commit**

```bash
git add openspec/changes/implement-internal-agent-runtime
git commit -m "docs: correct agent runtime product boundary"
```

---

### Task 2: Replace The Canonical Definition And Binding

**Files:**
- Modify: `test/office_graph/agent_runtime/persistence_migration_test.exs`
- Modify: `test/office_graph/agent_runtime/organization_binding_test.exs`
- Modify: `priv/repo/migrations/20260720120000_create_agent_runtime_foundation.exs`
- Modify: `priv/repo/migrations/20260721180000_add_agent_execution_leases.exs`
- Modify: `priv/repo/migrations/20260721230000_backfill_agent_runtime_governance.exs`
- Modify: `priv/repo/migrations/20260722181000_backfill_agent_runtime_delegation_capabilities.exs`
- Modify: `lib/office_graph/agent_runtime.ex`
- Modify: `lib/office_graph/agent_runtime/authority.ex`
- Modify: `lib/office_graph/authorization.ex`
- Modify: `test/office_graph/agent_runtime/invocation_test.exs`
- Modify: `test/office_graph/agent_runtime/authority_snapshot_test.exs`

**Interfaces:**
- Consumes: `AgentRuntime.bind_run_review_agent/2`.
- Produces: canonical `run-review` definition and scoped binding used by Tasks
  3-4.

- [ ] **Step 1: Write the failing migration assertions**

Change the migration test to load key `run-review` and assert:

```elixir
assert key == "run-review"
assert name == "Run Review"
assert requested_capabilities == [
         "agent.invoke",
         "agent.model.generate",
         "evidence.suggest",
         "proposal.create"
       ]
assert tool_allowlist == []
```

Also refute that a definition with key `openspec-review` exists.

- [ ] **Step 2: Write the failing binding API assertions**

Rename binding-test calls to:

```elixir
AgentRuntime.bind_run_review_agent(session_context, attrs)
```

Assert the definition key is `run-review` and that the provisioned system
principal is authorized for:

```elixir
[:agent_runtime_execute, :skeleton_read, :agent_model_generate,
 :agent_proposal_create, :agent_evidence_suggest]
```

Do not require repository or OpenSpec read authority.

- [ ] **Step 3: Write failing agent-authority intersection assertions**

In `invocation_test.exs`, remove `agent.model.generate` from the bound agent
principal after fixture creation, invoke the definition automatically, and
assert:

```elixir
assert {:error, {:unauthorized_agent_capabilities, ["agent.model.generate"]}} =
         AgentRuntime.invoke_system(operation, request)
```

Assert no execution is created.

In `authority_snapshot_test.exs`, create an execution, remove
`agent.model.generate` from the agent principal, and assert:

```elixir
assert {:error, :agent_authority_revoked} =
         AgentRuntime.revalidate_step(execution_id)
```

- [ ] **Step 4: Run the focused tests and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test \
  test/office_graph/agent_runtime/persistence_migration_test.exs \
  test/office_graph/agent_runtime/organization_binding_test.exs \
  test/office_graph/agent_runtime/invocation_test.exs \
  test/office_graph/agent_runtime/authority_snapshot_test.exs
```

Expected: failures because `run-review`, `bind_run_review_agent/2`, and agent
capability intersection do not yet exist.

- [ ] **Step 5: Correct the foundation and backfill migrations**

The foundation definition must use:

```sql
'run-review',
'Run Review',
'Reviews authorized Office Graph run context and proposes bounded follow-up.',
ARRAY['agent.invoke', 'agent.model.generate', 'proposal.create', 'evidence.suggest']::text[],
'deterministic',
ARRAY[]::text[],
ARRAY['message', 'finding', 'proposal', 'observation', 'evidence_candidate']::text[]
```

Change definition-specific `WHERE key = 'openspec-review'` clauses in later
migrations to `WHERE key = 'run-review'`.

Remove `openspec.read` from
`20260722181000_backfill_agent_runtime_delegation_capabilities.exs`; retain
provider-neutral `repository.read` only as a generic capability already
exercised by authority/approval tests.

- [ ] **Step 6: Rename and narrow the binding command**

In `lib/office_graph/agent_runtime.ex`:

```elixir
@canonical_definition_key "run-review"
@agent_capabilities [
  :agent_runtime_execute,
  :skeleton_read,
  :agent_model_generate,
  :agent_proposal_create,
  :agent_evidence_suggest
]
```

Rename both clauses to `bind_run_review_agent/2`, update the docstring, use an
agent email prefixed `run-review+`, and use idempotency scope
`agent-runtime:run-review:<organization_id>:<workspace_id>`.

Remove `agent_openspec_read: "openspec.read"` from
`OfficeGraph.Authorization`. Keep `agent_repository_read` unchanged because it
is provider-neutral and independently used by generic tool authority tests.

- [ ] **Step 7: Enforce the agent-principal capability intersection**

In `Authority.effective_capability_keys/3`, first intersect every requested
capability with `binding.agent_principal_id`; reject missing requested
capabilities with the existing sorted
`{:unauthorized_agent_capabilities, missing}` shape. If a delegator exists,
apply the delegator intersection second.

In pre-step revalidation, intersect every `snapshot.capability_keys` entry with
the execution's agent principal in addition to the existing runtime/skeleton
checks. Map a missing snapshotted capability to
`{:error, :agent_authority_revoked}` and preserve
`:integration_storage_unavailable`.

- [ ] **Step 8: Run focused tests and verify GREEN**

Run the exact command from Step 4.

Expected: all tests pass.

- [ ] **Step 9: Format and commit**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix format \
  lib/office_graph/agent_runtime.ex \
  lib/office_graph/agent_runtime/authority.ex \
  lib/office_graph/authorization.ex \
  priv/repo/migrations/20260720120000_create_agent_runtime_foundation.exs \
  priv/repo/migrations/20260721180000_add_agent_execution_leases.exs \
  priv/repo/migrations/20260721230000_backfill_agent_runtime_governance.exs \
  priv/repo/migrations/20260722181000_backfill_agent_runtime_delegation_capabilities.exs \
  test/office_graph/agent_runtime/persistence_migration_test.exs \
  test/office_graph/agent_runtime/organization_binding_test.exs \
  test/office_graph/agent_runtime/invocation_test.exs \
  test/office_graph/agent_runtime/authority_snapshot_test.exs
git add lib/office_graph/agent_runtime.ex \
  lib/office_graph/agent_runtime/authority.ex \
  lib/office_graph/authorization.ex \
  priv/repo/migrations test/office_graph/agent_runtime
git commit -m "refactor: make canonical agent product native"
```

---

### Task 3: Preserve Generic Storage Retry Semantics

**Files:**
- Modify: `test/office_graph/agent_runtime/execution_worker_test.exs`
- Modify: `lib/office_graph/agent_runtime/execution_worker.ex`

**Interfaces:**
- Consumes: existing `StorageResult.run/1` and `OutputRouter.route!/5`.
- Produces: bounded retry behavior when owning-domain persistence fails during
  output routing.

- [ ] **Step 1: Write the failing routing-storage regression**

Add a test-only router:

```elixir
defmodule StorageUnavailableOutputRouter do
  def route!(_operation, _execution, _context_package, _step_key, _output) do
    raise Ash.Error.Unknown, errors: []
  end
end
```

Configure it through `:agent_runtime_output_router`, perform the initial model
job, and assert:

```elixir
assert {:snooze, 1} = ExecutionWorker.perform(%{job | attempt: 1, max_attempts: 3})
assert execution.state == "retry_scheduled"
assert execution.failure_code == "integration_storage_unavailable"
assert request.state == "retry_scheduled"
assert request.failure_code == "integration_storage_unavailable"
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test test/office_graph/agent_runtime/execution_worker_test.exs
```

Expected: the injected router is not used or the exception escapes instead of
producing retry state.

- [ ] **Step 3: Normalize completion through the storage boundary**

Alias `StorageResult`. Resolve the router with:

```elixir
defp output_router do
  Application.get_env(:office_graph, :agent_runtime_output_router, OutputRouter)
end
```

Call `output_router().route!/5`. Wrap the completion transaction and
`normalize_step_transaction/1` inside `StorageResult.run/1`, so Ash/database
exceptions become `{:error, :integration_storage_unavailable}` before
`persist_adapter_result/4` selects retry behavior.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the exact command from Step 2.

Expected: all execution-worker tests pass.

- [ ] **Step 5: Format and commit**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix format \
  lib/office_graph/agent_runtime/execution_worker.ex \
  test/office_graph/agent_runtime/execution_worker_test.exs
git add lib/office_graph/agent_runtime/execution_worker.ex \
  test/office_graph/agent_runtime/execution_worker_test.exs
git commit -m "fix: preserve agent output storage retries"
```

---

### Task 4: Make Operator And API Surfaces Product Native

**Files:**
- Modify: `test/office_graph/node_conversations/commands_and_projection_test.exs`
- Modify: `test/office_graph_web/agent_governance_api_test.exs`
- Modify: `lib/office_graph/node_conversations.ex`
- Modify: `test/support/office_graph/agent_runtime_support.ex`

**Interfaces:**
- Consumes: canonical `run-review` binding from Task 2.
- Produces: product-native invocation target and affordance copy.

- [ ] **Step 1: Write failing projection assertions**

Update the run-conversation projection test to expect:

```elixir
assert invocation_affordance.description ==
         "Invoke the approved run review agent for this run context."

assert input_default(invocation_affordance, "requested_outcome") ==
         "Review the selected run, work packet, graph context, checks, and evidence, then propose bounded follow-up work."

refute "openspec.read" in requested_capabilities
refute "repository.read" in requested_capabilities
```

Update the governance API request outcome and capability input to the same
product-native values.

- [ ] **Step 2: Run projection/API tests and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test \
  test/office_graph/node_conversations/commands_and_projection_test.exs \
  test/office_graph_web/agent_governance_api_test.exs
```

Expected: failures showing the current `openspec-review` lookup/copy.

- [ ] **Step 3: Correct the projection and shared fixture**

In `NodeConversations`:

- select `definition.key = 'run-review'`;
- use unavailable copy `No approved run review agent is bound to this workspace.`;
- use enabled copy
  `Invoke the approved run review agent for this run context.`;
- use the exact requested outcome from Step 1.

In `AgentRuntimeSupport`, call `bind_run_review_agent/2` and use a
`bind-run-review-<suffix>` idempotency key. Its default requested capabilities
must be the definition's four capabilities, with invocation-control
capabilities removed where the existing helper already does so.

- [ ] **Step 4: Run projection/API tests and verify GREEN**

Run the exact command from Step 2.

Expected: all tests pass.

- [ ] **Step 5: Format and commit**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix format \
  lib/office_graph/node_conversations.ex \
  test/support/office_graph/agent_runtime_support.ex \
  test/office_graph/node_conversations/commands_and_projection_test.exs \
  test/office_graph_web/agent_governance_api_test.exs
git add lib/office_graph/node_conversations.ex \
  test/support/office_graph/agent_runtime_support.ex \
  test/office_graph/node_conversations/commands_and_projection_test.exs \
  test/office_graph_web/agent_governance_api_test.exs
git commit -m "refactor: make run review surfaces product native"
```

---

### Task 5: Remove Residual OpenSpec Product Semantics

**Files:**
- Modify: `test/office_graph/agent_runtime/delegation_capability_migration_test.exs`
- Modify: `test/office_graph/agent_runtime/governance_migration_test.exs`
- Modify: `test/office_graph/agent_runtime/adapter_registry_test.exs`
- Modify: `test/office_graph/agent_runtime/authority_snapshot_test.exs`
- Modify: `test/office_graph/agent_runtime/invocation_test.exs`
- Modify: `test/office_graph/agent_runtime/persistence_state_test.exs`
- Modify: `test/office_graph/agent_runtime/persistence_validation_test.exs`
- Modify additional product tests returned by the audit command only where they
  contain OpenSpec-specific product semantics.

**Interfaces:**
- Consumes: canonical definition and support helpers from Tasks 2-3.
- Produces: product/runtime tree with no OpenSpec feature semantics.

- [ ] **Step 1: Audit remaining product references**

Run:

```bash
rg -n -i "openspec" lib config priv test README.md flake.nix
```

Classify every hit:

- allowed: repository workflow docs, Nix development shell, OpenSpec validation,
  architecture conformance reading planning artifacts;
- forbidden: agent definitions, migrations, capabilities, product outcomes,
  operator/API copy, runtime fixtures, or runtime configuration.

- [ ] **Step 2: Update behavior tests to run-review semantics**

For each forbidden test hit:

- change definition lookup to `run-review`;
- change binding calls to `bind_run_review_agent/2`;
- replace requested outcomes with Office Graph run-review language;
- replace OpenSpec-specific capabilities with the canonical definition's
  capabilities;
- retain `repository.read` only in tests explicitly exercising generic tool,
  approval, or context-expansion authority.

Do not weaken lifecycle, replay, authorization, idempotency, migration,
credential, or persistence assertions.

- [ ] **Step 3: Run the agent-runtime and conversation suites**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test \
  test/office_graph/agent_runtime \
  test/office_graph/node_conversations \
  test/office_graph_web/agent_governance_api_test.exs
```

Expected: all tests pass.

- [ ] **Step 4: Prove the product/runtime boundary**

Run:

```bash
rg -n -i "openspec" lib config priv
```

Expected: no matches.

Run:

```bash
rg -n -i "openspec" test
```

Expected: only architecture/development-workflow tests that intentionally read
OpenSpec artifacts or execute OpenSpec validation; no agent-runtime,
conversation, API, migration, capability, product-copy, or fixture matches.

- [ ] **Step 5: Format and commit**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix format
git add test lib config priv
git commit -m "test: remove OpenSpec product assumptions"
```

---

### Task 6: Verify, Synchronize, And Archive The Corrected Change

**Files:**
- Modify: `openspec/changes/implement-internal-agent-runtime/tasks.md`
- Modify/archive files as directed by `openspec-archive-change`.

**Interfaces:**
- Consumes: corrected implementation from Tasks 1-5.
- Produces: verified durable specs and archived completed change.

- [ ] **Step 1: Run focused verification and mark Task 8.1**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  mix test \
  test/office_graph/agent_runtime \
  test/office_graph/node_conversations \
  test/office_graph_web/agent_governance_api_test.exs \
  test/office_graph/architecture
```

Expected: all tests pass. Then mark OpenSpec task 8.1 complete.

- [ ] **Step 2: Run the full canonical gate and mark Task 8.2**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  env MIX_ENV=test mix verify
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate implement-internal-agent-runtime --strict
git diff --check
```

Expected: all commands exit 0. Then mark OpenSpec task 8.2 complete and re-run
strict change validation.

- [ ] **Step 3: Synchronize and archive**

Invoke `openspec-sync-specs` for `implement-internal-agent-runtime`, verify the
durable specs, then invoke `openspec-archive-change`. Mark task 8.3 complete as
part of the archived task artifact.

- [ ] **Step 4: Verify the archived state**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate --specs --strict
nix --extra-experimental-features 'nix-command flakes' develop --command \
  openspec validate --changes --strict
git diff --check
git status --short --branch
```

Expected: durable specs valid, no invalid active changes, clean patch syntax,
and only intended branch changes.

- [ ] **Step 5: Commit**

```bash
git add openspec docs
git commit -m "docs: archive corrected agent runtime change"
```
