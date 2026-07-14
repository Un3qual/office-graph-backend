# Internal Agent Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a governed, run-linked internal agent runtime that assembles authorized context, supervises deterministic model/tool steps durably, and routes output only to proposals, evidence candidates, and run-aware conversations.

**Architecture:** AgentRuntime owns definitions, bindings, executions, authority snapshots, context packages, adapter requests, approvals, and durable step orchestration while existing domains retain business records. Every execution is linked to a work run and generic system operation; model/tool output is treated as untrusted and can reach product state only through named proposal, evidence-candidate, observation, or conversation commands.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix 1.8, Ash 3, AshPostgres, Ecto/Postgres, Oban 2.x, Absinthe/AshGraphql, AshJsonApi, React 19, React Router, Relay, TypeScript, Vitest, OpenSpec, Nix.

## Global Constraints

- Enter the project Nix flake for every runtime and CLI command.
- Implement only after typed relationships and the GitHub change's generic system-operation contract are present in branch ancestry.
- Treat `openspec/changes/implement-internal-agent-runtime/` as the behavioral source of truth.
- Every MVP execution is linked to an organization, workspace, graph item, and work run.
- Persist immutable authority and context snapshots; revalidate mutable principals, credentials, grants, approvals, and tool eligibility before each step.
- Model and tool output cannot directly mutate business records, write externally, or complete verification.
- Normal verification uses deterministic model/tool adapters and does not require a hosted model vendor or GitHub.
- Retain typed metadata, hashes, references, classifications, and safe summaries by default; do not retain raw prompts, responses, tool payloads, or secrets.
- Add one focused run-aware operator surface; do not add general chat, agent administration, a marketplace, or a workflow builder.
- Human identity/governance administration remains deferred.

---

### Task 1: Runtime Persistence, Definitions, And Binding

**Files:**
- Create: `priv/repo/migrations/20260713120000_create_agent_runtime_resources.exs`
- Modify: `lib/office_graph/agent_runtime.ex`
- Create: `lib/office_graph/agent_runtime/domain.ex`
- Create: `lib/office_graph/agent_runtime/agent_definition.ex`
- Create: `lib/office_graph/agent_runtime/agent_binding.ex`
- Create: `lib/office_graph/agent_runtime/agent_execution.ex`
- Create: `lib/office_graph/agent_runtime/authority_snapshot.ex`
- Create: `lib/office_graph/agent_runtime/context_package.ex`
- Create: `lib/office_graph/agent_runtime/context_entry.ex`
- Create: `lib/office_graph/agent_runtime/execution_step.ex`
- Create: `lib/office_graph/agent_runtime/model_request.ex`
- Create: `lib/office_graph/agent_runtime/tool_request.ex`
- Create: `lib/office_graph/agent_runtime/approval_request.ex`
- Create: `lib/office_graph/agent_runtime/context_expansion_request.ex`
- Create: `lib/office_graph/node_conversations.ex`
- Create: `lib/office_graph/node_conversations/domain.ex`
- Create: `lib/office_graph/node_conversations/conversation.ex`
- Create: `lib/office_graph/node_conversations/message.ex`
- Create: `lib/office_graph/agent_runtime/definition_commands.ex`
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph.ex`
- Test: `test/office_graph/agent_runtime/resource_contracts_test.exs`
- Test: `test/office_graph/agent_runtime/definition_binding_test.exs`
- Modify: `test/office_graph/architecture/ash_api_ledger_conformance_test.exs`

**Interfaces:**
- Produces: migration-owned definition key `openspec_review` with declared model adapter, read-only tool keys, context policy, default autonomy envelope, and lifecycle.
- Produces: `AgentRuntime.bind_definition(session, operation, attrs) :: {:ok, AgentBinding.t()} | {:error, term()}`.
- `attrs` requires `definition_key`, `organization_id`, `workspace_id`, `agent_principal_id`, and `credential_ids`; bindings are organization-owned, workspace-constrained, versioned, and lifecycle-aware.
- Produces human action keys `agent.bind`, `agent.invoke`, `agent.cancel`, `agent.approval.resolve`, `agent.context_expansion.resolve`, and `agent.message.append`; automatic invocation uses the shared system-operation contract.

- [ ] **Step 1: Write persistence and binding tests first**

```elixir
defmodule OfficeGraph.AgentRuntime.ResourceContractsTest do
  use OfficeGraph.DataCase, async: true

  test "the OpenSpec review definition is migration-owned and proposal-first" do
    assert {:ok, definition} = AgentRuntime.get_definition("openspec_review")
    assert definition.lifecycle == "active"
    assert definition.model_adapter_key == "deterministic_review"
    assert definition.tool_keys == ["repository_read", "openspec_read"]
    assert definition.external_write_allowed == false
    assert definition.direct_mutation_allowed == false
  end

  test "binding validates scope, principal kind, and credential references", context do
    assert {:ok, binding} =
             AgentRuntime.bind_definition(context.session, context.operation, %{
               definition_key: "openspec_review",
               organization_id: context.organization.id,
               workspace_id: context.workspace.id,
               agent_principal_id: context.agent_principal.id,
               credential_ids: []
             })

    assert binding.version == 1
    assert binding.lifecycle == "active"
  end
end
```

- [ ] **Step 2: Run resource tests and observe the empty boundary**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/resource_contracts_test.exs test/office_graph/agent_runtime/definition_binding_test.exs`

Expected: FAIL because AgentRuntime has no resources or exports.

- [ ] **Step 3: Add typed relational resources and the migration-owned definition**

Use separate tables for every listed resource. Enforce lifecycle/state checks, organization/workspace/run foreign keys, immutable snapshot/version identities, one active binding per definition/workspace, one completion per execution-step identity, and bounded safe-summary fields. Install the definition in migration `up/0`; do not expose definition mutation through APIs.

```elixir
defmodule OfficeGraph.AgentRuntime do
  @moduledoc "Public boundary for governed agent orchestration."

  use Boundary,
    deps: [
      OfficeGraph,
      OfficeGraph.Authorization,
      OfficeGraph.Audit,
      OfficeGraph.DurableDelivery,
      OfficeGraph.NodeConversations,
      OfficeGraph.Operations,
      OfficeGraph.Projections,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Revisions,
      OfficeGraph.Runs,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph
    ],
    exports: []

  defdelegate get_definition(key), to: OfficeGraph.AgentRuntime.DefinitionCommands
  defdelegate bind_definition(session, operation, attrs),
    to: OfficeGraph.AgentRuntime.DefinitionCommands
end
```

- [ ] **Step 4: Implement the authorized binding transaction**

```elixir
def bind_definition(session, operation, attrs) do
  with :ok <- Operations.validate_operation_context(session, operation),
       :ok <- Authorization.authorize_operation(session, operation, :agent_bind),
       {:ok, definition} <- get_definition(attrs.definition_key),
       {:ok, principal} <- validate_agent_principal(session, attrs.agent_principal_id),
       :ok <- validate_binding_scope(session, attrs),
       :ok <- validate_credentials(session, definition, attrs.credential_ids) do
    persist_binding_with_trace(session, operation, definition, principal, attrs)
  end
end
```

Create the backend agent principal through the supported bootstrap/binding command in tests and development fixtures; do not add an agent-administration transport.

- [ ] **Step 5: Verify migrations, resources, binding, and architecture ledgers**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix ecto.reset`

Expected: PASS.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/resource_contracts_test.exs test/office_graph/agent_runtime/definition_binding_test.exs test/office_graph/architecture`

Expected: PASS with no public definition CRUD.

- [ ] **Step 6: Commit runtime persistence**

```bash
git add priv/repo/migrations/20260713120000_create_agent_runtime_resources.exs lib/office_graph/agent_runtime.ex lib/office_graph/agent_runtime lib/office_graph/node_conversations.ex lib/office_graph/node_conversations lib/office_graph/operations.ex lib/office_graph.ex test/office_graph/agent_runtime test/office_graph/architecture
git commit -m "feat: add agent runtime persistence"
```

### Task 2: Typed Model And Tool Adapter Contracts

**Files:**
- Create: `lib/office_graph/agent_runtime/model_adapter.ex`
- Create: `lib/office_graph/agent_runtime/model_manifest.ex`
- Create: `lib/office_graph/agent_runtime/model_input.ex`
- Create: `lib/office_graph/agent_runtime/model_output.ex`
- Create: `lib/office_graph/agent_runtime/tool_adapter.ex`
- Create: `lib/office_graph/agent_runtime/tool_manifest.ex`
- Create: `lib/office_graph/agent_runtime/tool_input.ex`
- Create: `lib/office_graph/agent_runtime/tool_output.ex`
- Create: `lib/office_graph/agent_runtime/adapter_result.ex`
- Create: `lib/office_graph/agent_runtime/adapter_registry.ex`
- Create: `lib/office_graph/agent_runtime/adapters/deterministic_model.ex`
- Create: `lib/office_graph/agent_runtime/adapters/deterministic_tool.ex`
- Modify: `config/test.exs`
- Test: `test/office_graph/agent_runtime/model_adapter_conformance_test.exs`
- Test: `test/office_graph/agent_runtime/tool_adapter_conformance_test.exs`
- Test: `test/office_graph/agent_runtime/adapter_registry_test.exs`

**Interfaces:**
- Model behavior: `manifest/0`, `invoke(%ModelInput{})`, and `cancel(request_id)`.
- Tool behavior: `manifest/0`, `invoke(%ToolInput{})`, and `cancel(request_id)`.
- Produces: `AdapterResult.normalize/1 :: {:ok, ModelOutput.t() | ToolOutput.t()} | {:error, {:retryable | :terminal | :cancelled, atom()}}`.
- Manifests declare schemas, capability keys, credential kinds, sensitivity, external-write posture, timeout, token/work budgets, output classification, and idempotency support.

- [ ] **Step 1: Write shared adapter conformance tests**

```elixir
for adapter <- [DeterministicModel] do
  test "#{inspect(adapter)} has a complete fail-closed manifest" do
    manifest = unquote(adapter).manifest()
    assert manifest.key != ""
    assert is_map(manifest.input_schema)
    assert is_map(manifest.output_schema)
    assert manifest.timeout_ms in 1_000..120_000
    assert manifest.external_write == false
    assert manifest.raw_retention == false
  end
end

test "malformed output is terminal and retained only as safe metadata", context do
  configure_model_result(%{"unexpected" => "shape"})

  assert {:error, {:terminal, :malformed_model_output}} =
           DeterministicModel.invoke(context.input)

  refute retained_request!(context.input.request_id).safe_summary =~ "unexpected"
end
```

- [ ] **Step 2: Run conformance tests and observe absent adapter types**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/model_adapter_conformance_test.exs test/office_graph/agent_runtime/tool_adapter_conformance_test.exs test/office_graph/agent_runtime/adapter_registry_test.exs`

Expected: FAIL because the behaviors, manifests, typed inputs/outputs, and registry do not exist.

- [ ] **Step 3: Implement provider-neutral behaviors and typed results**

```elixir
defmodule OfficeGraph.AgentRuntime.ModelAdapter do
  alias OfficeGraph.AgentRuntime.{ModelInput, ModelManifest, ModelOutput}

  @callback manifest() :: ModelManifest.t()
  @callback invoke(ModelInput.t()) ::
              {:ok, ModelOutput.t()}
              | {:error, {:retryable | :terminal | :cancelled, atom()}}
  @callback cancel(Ecto.UUID.t()) :: :ok | {:error, :not_found}
end

defmodule OfficeGraph.AgentRuntime.ToolAdapter do
  alias OfficeGraph.AgentRuntime.{ToolInput, ToolManifest, ToolOutput}

  @callback manifest() :: ToolManifest.t()
  @callback invoke(ToolInput.t()) ::
              {:ok, ToolOutput.t()}
              | {:error, {:retryable | :terminal | :cancelled, atom()}}
  @callback cancel(Ecto.UUID.t()) :: :ok | {:error, :not_found}
end
```

The registry is configured with known modules and validates that the configured key equals the manifest key. Deterministic adapters consume fixture IDs, validate schemas, enforce budgets/timeouts/idempotency, and return typed proposal/evidence/message outputs without storing fixture bodies.

- [ ] **Step 4: Run adapter conformance and cancellation tests**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/model_adapter_conformance_test.exs test/office_graph/agent_runtime/tool_adapter_conformance_test.exs test/office_graph/agent_runtime/adapter_registry_test.exs`

Expected: PASS for success, retry, terminal, malformed, limit, idempotency, and cancellation cases.

- [ ] **Step 5: Commit adapter contracts**

```bash
git add lib/office_graph/agent_runtime config/test.exs test/office_graph/agent_runtime/model_adapter_conformance_test.exs test/office_graph/agent_runtime/tool_adapter_conformance_test.exs test/office_graph/agent_runtime/adapter_registry_test.exs
git commit -m "feat: add typed agent adapters"
```

### Task 3: Invocation, Authority Snapshot, And Context Packages

**Files:**
- Create: `lib/office_graph/agent_runtime/invocation_request.ex`
- Create: `lib/office_graph/agent_runtime/invocation_commands.ex`
- Create: `lib/office_graph/agent_runtime/authority.ex`
- Create: `lib/office_graph/agent_runtime/context_assembler.ex`
- Create: `lib/office_graph/agent_runtime/context_policy.ex`
- Modify: `lib/office_graph/agent_runtime.ex`
- Modify: `lib/office_graph/authorization.ex`
- Modify: `lib/office_graph/runs.ex`
- Modify: `lib/office_graph/projections.ex`
- Test: `test/office_graph/agent_runtime/invocation_test.exs`
- Test: `test/office_graph/agent_runtime/authority_snapshot_test.exs`
- Test: `test/office_graph/agent_runtime/context_package_test.exs`

**Interfaces:**
- Produces: `AgentRuntime.invoke(session, operation, %InvocationRequest{})` for human invocation.
- Produces: `AgentRuntime.invoke_system(system_operation, %InvocationRequest{})` for declared automatic invocation using the unchanged generic system-operation schema.
- `InvocationRequest` requires definition/binding, graph item, run, origin, mode, idempotency key, and requested capabilities; it accepts no raw prompt or arbitrary tool list.
- Produces immutable `AuthoritySnapshot` and versioned `ContextPackage` before enqueue.

- [ ] **Step 1: Write run-link, replay, authority, and redaction tests**

```elixir
test "human invocation snapshots the effective intersection and replays", context do
  request = InvocationRequest.new!(%{
    binding_id: context.binding.id,
    graph_item_id: context.graph_item.id,
    run_id: context.run.id,
    origin: "operator",
    mode: "review",
    idempotency_key: "review:run-12:item-4",
    requested_capabilities: ["graph.read", "proposal.create"]
  })

  assert {:ok, first} = AgentRuntime.invoke(context.session, context.operation, request)
  assert {:ok, replay} = AgentRuntime.invoke(context.session, context.operation, request)
  assert replay.id == first.id
  assert first.authority_snapshot.effective_capabilities == ["graph.read", "proposal.create"]
end

test "context records redaction rationale without leaking the target", context do
  assert {:ok, package} = ContextAssembler.assemble(context.execution)
  restricted = Enum.find(package.entries, &(&1.posture == "redacted"))
  assert restricted.safe_reason == "endpoint_not_authorized"
  assert restricted.reference_id == nil
  refute inspect(restricted) =~ context.restricted_title
end
```

- [ ] **Step 2: Run invocation/context tests and observe missing orchestration**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/invocation_test.exs test/office_graph/agent_runtime/authority_snapshot_test.exs test/office_graph/agent_runtime/context_package_test.exs`

Expected: FAIL because invocation, authority computation, and context assembly are absent.

- [ ] **Step 3: Implement fail-closed invocation and immutable snapshots**

```elixir
def invoke(session, operation, %InvocationRequest{} = request) do
  with :ok <- Operations.validate_operation_context(session, operation),
       {:ok, binding} <- load_active_binding(session, request.binding_id),
       {:ok, run} <- Runs.get_authorized_run(session, request.run_id),
       :ok <- validate_graph_item_run_scope(session, request.graph_item_id, run),
       {:ok, authority} <- Authority.compute(session, operation, binding, request) do
    create_execution_snapshot_context_and_job(session, operation, binding, run, request, authority)
  end
end
```

`invoke_system/2` validates the system operation kind and declared automatic trigger basis, then uses the same internal transaction. That transaction writes execution, immutable authority snapshot, immutable context package/entries, first step, domain event, and unique Oban job together.

- [ ] **Step 4: Implement context assembly through existing projections**

```elixir
def assemble(execution) do
  with {:ok, root} <- Projections.agent_graph_item(execution.authority_snapshot, execution.graph_item_id),
       {:ok, neighbors} <- Projections.agent_relationship_context(execution.authority_snapshot, root),
       {:ok, run_context} <- Runs.agent_context(execution.authority_snapshot, execution.run_id) do
    persist_package(execution, [root | neighbors] ++ run_context)
  end
end
```

Every entry records `included`, `redacted`, `omitted`, `restricted`, or `expansion_required`, plus source kind/version/hash and a stable safe rationale. Never query graph tables directly from adapters or workers.

- [ ] **Step 5: Verify human/system invocation and cross-tenant failure**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/invocation_test.exs test/office_graph/agent_runtime/authority_snapshot_test.exs test/office_graph/agent_runtime/context_package_test.exs test/office_graph/operations/system_operations_test.exs`

Expected: PASS; the agent path uses the existing system-operation table and constructor without schema changes.

- [ ] **Step 6: Commit invocation and context**

```bash
git add lib/office_graph/agent_runtime.ex lib/office_graph/agent_runtime lib/office_graph/authorization.ex lib/office_graph/runs.ex lib/office_graph/projections.ex test/office_graph/agent_runtime
git commit -m "feat: invoke agents with authorized context"
```

### Task 4: Durable Execution State Machine

**Files:**
- Create: `lib/office_graph/agent_runtime/execution_state.ex`
- Create: `lib/office_graph/agent_runtime/execution_commands.ex`
- Create: `lib/office_graph/agent_runtime/execution_worker.ex`
- Create: `lib/office_graph/agent_runtime/step_worker.ex`
- Create: `lib/office_graph/agent_runtime/recovery_worker.ex`
- Create: `lib/office_graph/agent_runtime/step_lease.ex`
- Modify: `lib/office_graph/agent_runtime.ex`
- Modify: `lib/office_graph/durable_delivery.ex`
- Modify: `lib/office_graph/runs.ex`
- Test: `test/office_graph/agent_runtime/execution_state_test.exs`
- Test: `test/office_graph/agent_runtime/execution_worker_test.exs`
- Test: `test/office_graph/agent_runtime/execution_concurrency_test.exs`
- Test: `test/office_graph/agent_runtime/recovery_test.exs`

**Interfaces:**
- Execution states: `queued`, `running`, `waiting_approval`, `waiting_context`, `retry_scheduled`, `completed`, `failed`, and `cancelled`.
- Produces: `AgentRuntime.cancel(session, operation, execution_id, expected_version)`.
- Workers use `{execution_id, step_key, attempt}` identities, a bounded lease, unique jobs, classified adapter results, and completion-before-next-dispatch ordering.

- [ ] **Step 1: Write state, duplicate, cancellation, and recovery tests**

```elixir
test "duplicate jobs execute a step effect once", context do
  job = %Oban.Job{args: %{"execution_id" => context.execution.id, "step_key" => "model:review"}}

  results =
    [job, job]
    |> Task.async_stream(&StepWorker.perform/1, ordered: false, max_concurrency: 2)
    |> Enum.map(fn {:ok, result} -> result end)

  assert Enum.all?(results, &(&1 == :ok))
  assert count_model_requests(context.execution.id, "model:review") == 1
  assert count_completed_steps(context.execution.id, "model:review") == 1
end

test "expired running leases recover without duplicating completed work", context do
  expire_lease!(context.running_step)
  assert :ok = RecoveryWorker.perform(%Oban.Job{args: %{"execution_id" => context.execution.id}})
  assert execution!(context.execution.id).state == "retry_scheduled"
  assert count_step_jobs(context.running_step.id) == 1
end

test "revoked mutable authority stops the next step before adapter invocation", context do
  revoke_principal!(context.execution.agent_principal_id)

  assert {:cancel, :agent_principal_inactive} =
           StepWorker.perform(%Oban.Job{
             args: %{"execution_id" => context.execution.id, "step_key" => "model:review"}
           })

  assert model_invocation_count(context.execution.id) == 0
  assert execution!(context.execution.id).state == "failed"
end
```

- [ ] **Step 2: Run worker tests and observe absent state machine**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/execution_state_test.exs test/office_graph/agent_runtime/execution_worker_test.exs test/office_graph/agent_runtime/execution_concurrency_test.exs test/office_graph/agent_runtime/recovery_test.exs`

Expected: FAIL because durable steps, leases, transitions, and recovery are absent.

- [ ] **Step 3: Implement the pure transition policy and versioned persistence**

```elixir
@transitions %{
  "queued" => MapSet.new(["running", "cancelled"]),
  "running" => MapSet.new(["waiting_approval", "waiting_context", "retry_scheduled", "completed", "failed", "cancelled"]),
  "waiting_approval" => MapSet.new(["queued", "failed", "cancelled"]),
  "waiting_context" => MapSet.new(["queued", "failed", "cancelled"]),
  "retry_scheduled" => MapSet.new(["queued", "failed", "cancelled"]),
  "completed" => MapSet.new(),
  "failed" => MapSet.new(),
  "cancelled" => MapSet.new()
}

def transition(from, to) do
  if MapSet.member?(Map.fetch!(@transitions, from), to),
    do: :ok,
    else: {:error, {:invalid_execution_transition, from, to}}
end
```

Lock execution and step rows before versioned transitions. Call
`Authority.revalidate_step(execution, step)` before acquiring a lease or
invoking an adapter, and fail closed if the principal, credential, grant,
approval, binding, or tool is no longer eligible. Acquire/renew a lease before
adapter invocation, persist the typed result and step completion, release the
lease, then enqueue the next unique job. Retry only classified retryable results
within attempt/time budgets.

- [ ] **Step 4: Implement explicit cancellation and restart recovery**

```elixir
def cancel(session, operation, execution_id, expected_version) do
  with :ok <- Operations.validate_operation_context(session, operation),
       :ok <- Authorization.authorize_operation(session, operation, :agent_cancel),
       {:ok, execution} <- lock_execution(session, execution_id),
       :ok <- require_version(execution, expected_version),
       :ok <- ExecutionState.transition(execution.state, "cancelled") do
    cancel_active_adapter_requests_and_persist(execution, operation)
  end
end
```

Recovery scans only bounded expired leases, skips terminal/completed steps, records a safe recovery event, and enqueues one replacement job. Agent completion records a child-run timeline event but never changes a parent verification result.

- [ ] **Step 5: Run state-machine, concurrency, recovery, and run tests**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/execution_state_test.exs test/office_graph/agent_runtime/execution_worker_test.exs test/office_graph/agent_runtime/execution_concurrency_test.exs test/office_graph/agent_runtime/recovery_test.exs test/office_graph/work_packets/work_run_contracts_test.exs`

Expected: PASS with one effect per step identity and no verification completion side effect.

- [ ] **Step 6: Commit durable orchestration**

```bash
git add lib/office_graph/agent_runtime.ex lib/office_graph/agent_runtime lib/office_graph/durable_delivery.ex lib/office_graph/runs.ex test/office_graph/agent_runtime test/office_graph/work_packets/work_run_contracts_test.exs
git commit -m "feat: supervise agent executions durably"
```

### Task 5: Approvals, Context Expansion, And Output Routing

**Files:**
- Create: `lib/office_graph/agent_runtime/approval_commands.ex`
- Create: `lib/office_graph/agent_runtime/output_router.ex`
- Create: `lib/office_graph/agent_runtime/output_contract.ex`
- Modify: `lib/office_graph/agent_runtime/execution_worker.ex`
- Modify: `lib/office_graph/agent_runtime.ex`
- Modify: `lib/office_graph/proposed_changes.ex`
- Modify: `lib/office_graph/verification.ex`
- Modify: `lib/office_graph/runs.ex`
- Modify: `lib/office_graph_web/graphql/operator_commands/mutations.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/resolvers/agents.ex`
- Create: `lib/office_graph_web/json_api/operator_commands/agents_controller.ex`
- Modify: `lib/office_graph_web/router.ex`
- Test: `test/office_graph/agent_runtime/approval_commands_test.exs`
- Test: `test/office_graph/agent_runtime/output_router_test.exs`
- Test: `test/office_graph_web/agent_commands_api_test.exs`

**Interfaces:**
- Produces: versioned approve/deny/cancel commands for approval and context-expansion request IDs.
- Produces: `OutputRouter.route(execution, step, %OutputContract{}) :: {:ok, [output_reference]} | {:error, term()}`.
- Allowed output kinds: `message`, `review_finding_proposal`, `graph_change_proposal`, `execution_observation`, and `evidence_candidate`.

- [ ] **Step 1: Write stale, expiry, resume, and mutation-safety tests**

```elixir
test "approval resumes only its matching waiting step", context do
  assert {:ok, resolved} =
           AgentRuntime.approve(
             context.session,
             context.operation,
             context.approval.id,
             context.approval.version
           )

  assert resolved.state == "approved"
  assert count_step_jobs(context.approval.execution_step_id) == 1
  assert count_step_jobs(context.other_waiting_step.id) == 0
end

test "agent output cannot directly mutate or verify product state", context do
  output = %OutputContract{kind: "verification_result", body: %{"result" => "passed"}}
  assert {:error, {:unsupported_agent_output, "verification_result"}} =
           OutputRouter.route(context.execution, context.step, output)
  assert verification_result_count(context.run.id) == 0
end

test "context expansion creates a new package version without mutating the old one", context do
  original = context.expansion.context_package

  assert {:ok, resolved} =
           AgentRuntime.approve_context_expansion(
             context.session,
             context.operation,
             context.expansion.id,
             context.expansion.version
           )

  assert resolved.context_package.version == original.version + 1
  assert resolved.context_package.previous_package_id == original.id
  assert context_package!(original.id).content_hash == original.content_hash
end
```

- [ ] **Step 2: Run approval/output tests and observe absent commands/router**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/approval_commands_test.exs test/office_graph/agent_runtime/output_router_test.exs test/office_graph_web/agent_commands_api_test.exs`

Expected: FAIL because durable request resolution and output routing do not exist.

- [ ] **Step 3: Implement versioned resolution with exact step resumption**

```elixir
def approve(session, operation, request_id, expected_version) do
  resolve(session, operation, request_id, expected_version, "approved")
end

def deny(session, operation, request_id, expected_version) do
  resolve(session, operation, request_id, expected_version, "denied")
end

def cancel_request(session, operation, request_id, expected_version) do
  resolve(session, operation, request_id, expected_version, "cancelled")
end
```

Approval and context-expansion commands remain distinct public functions even
though they share locking/version helpers. The resolver validates
scope/capability/sensitivity/expiry/version, records operation/audit/revision
provenance, changes only its matching execution step, and enqueues exactly one
resume job. An approved context expansion creates a new immutable package
version linked to the decision and prior package.

- [ ] **Step 4: Implement an explicit output allowlist over owning commands**

```elixir
def route(execution, step, %OutputContract{kind: "graph_change_proposal"} = output) do
  ProposedChanges.create_from_agent(execution.authority_snapshot, execution.operation, %{
    execution_id: execution.id,
    execution_step_id: step.id,
    change: output.body
  })
end

def route(execution, step, %OutputContract{kind: "evidence_candidate"} = output) do
  Verification.create_evidence_candidate_from_agent(
    execution.authority_snapshot,
    execution.operation,
    execution.run_id,
    %{execution_step_id: step.id, candidate: output.body}
  )
end

def route(_execution, _step, %OutputContract{kind: kind}) do
  {:error, {:unsupported_agent_output, kind}}
end
```

Define equally explicit clauses for messages, finding proposals, and observations. There is no fallback that invokes a resource/module/function named by model output.

- [ ] **Step 5: Verify domain and transport behavior**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/approval_commands_test.exs test/office_graph/agent_runtime/output_router_test.exs test/office_graph_web/agent_commands_api_test.exs test/office_graph/proposed_changes test/office_graph/verification test/office_graph/work_packets/work_run_evidence_test.exs`

Expected: PASS; agent material remains proposed or candidate state until existing human workflows accept it.

- [ ] **Step 6: Commit approvals and output routing**

```bash
git add lib/office_graph/agent_runtime.ex lib/office_graph/agent_runtime lib/office_graph/proposed_changes.ex lib/office_graph/verification.ex lib/office_graph/runs.ex lib/office_graph_web test/office_graph/agent_runtime test/office_graph_web/agent_commands_api_test.exs test/office_graph/proposed_changes test/office_graph/verification test/office_graph/work_packets/work_run_evidence_test.exs
git commit -m "feat: route governed agent outputs"
```

### Task 6: Run-Aware Conversations And Operator Surface

**Files:**
- Create: `lib/office_graph/node_conversations/commands.ex`
- Create: `lib/office_graph/node_conversations/queries.ex`
- Create: `lib/office_graph/projections/agent_execution.ex`
- Modify: `lib/office_graph/projections/operator_workflow.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/queries.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/types.ex`
- Modify: `lib/office_graph_web/graphql/operator_commands/mutations.ex`
- Modify: `assets/schema.graphql`
- Create: `assets/app/routes/operator/components/AgentRunPanel.tsx`
- Create: `assets/app/routes/operator/components/AgentConversation.tsx`
- Create: `assets/app/routes/operator/components/AgentApprovalCard.tsx`
- Create: `assets/app/routes/operator/agentWorkflow.ts`
- Create: `assets/app/routes/operator/agentWorkflow.test.tsx`
- Modify: `assets/app/routes/operator/route.tsx`
- Modify: `assets/app/routes/operator/data.ts`
- Modify: `assets/app/routes/operator/types.ts`
- Modify: `assets/app/styles/global.css`
- Test: `test/office_graph/node_conversations/commands_test.exs`
- Test: `test/office_graph/node_conversations/queries_test.exs`
- Test: `test/office_graph/projections/agent_execution_test.exs`
- Test: `test/office_graph_web/agent_conversation_graphql_test.exs`
- Modify: `assets/app/routes/operator/route.reads.test.tsx`
- Modify: `assets/app/routes/operator/route.commands.test.tsx`
- Modify: `assets/app/routes/operator/route.errors.test.tsx`

**Interfaces:**
- Produces: node/run-scoped conversation and message commands with human/agent author provenance, visibility, operation, execution/step links, and optional proposal/domain-action references.
- Operator UI supports invocation, message viewing, cancellation, approval/denial, context expansion resolution, execution status, and conflict refresh for one selected run.
- UI does not expose definition/binding administration or unscoped chat.

- [ ] **Step 1: Write conversation provenance and replay tests**

```elixir
test "agent messages retain execution provenance and replay once", context do
  attrs = %{
    conversation_id: context.conversation.id,
    idempotency_key: "execution:#{context.execution.id}:step:#{context.step.id}:message",
    body_summary: "Two specification gaps found.",
    execution_id: context.execution.id,
    execution_step_id: context.step.id,
    visibility: "workspace"
  }

  assert {:ok, first} = NodeConversations.append_agent_message(context.authority, context.operation, attrs)
  assert {:ok, replay} = NodeConversations.append_agent_message(context.authority, context.operation, attrs)
  assert replay.id == first.id
  assert replay.run_id == context.execution.run_id
end
```

- [ ] **Step 2: Write the operator interaction test before UI code**

```tsx
it("resolves an approval and refreshes the selected run", async () => {
  const user = userEvent.setup()
  renderOperatorRoute({fixture: agentWaitingApprovalFixture})

  await user.click(screen.getByRole("button", {name: "Approve read-only context"}))

  expect(commitMutation).toHaveBeenCalledWith(
    expect.objectContaining({approvalRequestId: "approval-1", expectedVersion: 3}),
  )
  expect(refreshSelectedRun).toHaveBeenCalledTimes(1)
})
```

- [ ] **Step 3: Run backend and frontend tests and observe missing conversation surface**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/node_conversations test/office_graph/projections/agent_execution_test.exs test/office_graph_web/agent_conversation_graphql_test.exs`

Expected: FAIL because commands, projections, and GraphQL fields are absent.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'cd assets && pnpm vitest run app/routes/operator/agentWorkflow.test.tsx app/routes/operator/route.reads.test.tsx app/routes/operator/route.commands.test.tsx app/routes/operator/route.errors.test.tsx'`

Expected: FAIL because the run-aware agent components and workflow do not exist.

- [ ] **Step 4: Implement scoped conversation commands and projections**

```elixir
def append_agent_message(authority, operation, attrs) do
  with :ok <- Authority.validate_snapshot(authority),
       {:ok, conversation} <- authorized_conversation(authority, attrs.conversation_id),
       :ok <- validate_execution_scope(conversation, attrs.execution_id, attrs.execution_step_id) do
    persist_message_with_trace(authority, operation, conversation, attrs)
  end
end
```

Batch messages, pending requests, execution summaries, and safe context references in the selected run projection. Redact restricted references using the stored context-entry posture rather than re-exposing source data.

- [ ] **Step 5: Implement the focused operator panel**

```tsx
export function AgentRunPanel({run, onRefresh}: AgentRunPanelProps) {
  if (!run.agentExecution) return <p>No agent execution is attached to this run.</p>

  return (
    <section aria-labelledby="agent-run-heading">
      <h2 id="agent-run-heading">Agent review</h2>
      <AgentConversation messages={run.agentExecution.messages} />
      {run.agentExecution.pendingApprovals.map((approval) => (
        <AgentApprovalCard key={approval.id} approval={approval} onResolved={onRefresh} />
      ))}
    </section>
  )
}
```

Use existing command form feedback and Relay mutation conventions. Preserve all server field errors, focus the first invalid control, refresh on stale-version conflicts, and keep status/read views accessible without adding a new route.

- [ ] **Step 6: Regenerate artifacts and verify the complete surface**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'cd assets && pnpm relay && pnpm vitest run app/routes/operator/agentWorkflow.test.tsx app/routes/operator/route.reads.test.tsx app/routes/operator/route.commands.test.tsx app/routes/operator/route.errors.test.tsx && pnpm typecheck'`

Expected: `assets/schema.graphql` and Relay artifacts regenerate, focused tests pass, and TypeScript checking passes.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/node_conversations test/office_graph/projections/agent_execution_test.exs test/office_graph_web/agent_conversation_graphql_test.exs`

Expected: PASS with run/graph scope and provenance preserved.

- [ ] **Step 7: Commit conversations and operator UI**

```bash
git add lib/office_graph/node_conversations.ex lib/office_graph/node_conversations lib/office_graph/projections lib/office_graph_web assets/schema.graphql assets/app/routes/operator assets/app/styles/global.css test/office_graph/node_conversations test/office_graph/projections/agent_execution_test.exs test/office_graph_web/agent_conversation_graphql_test.exs
git commit -m "feat: add run aware agent conversations"
```

### Task 7: First Deterministic OpenSpec Review Agent

**Files:**
- Create: `lib/office_graph/agent_runtime/tools/repository_read.ex`
- Create: `lib/office_graph/agent_runtime/tools/openspec_read.ex`
- Create: `lib/office_graph/agent_runtime/agents/openspec_review.ex`
- Create: `lib/office_graph/agent_runtime/agents/openspec_review_workflow.ex`
- Modify: `lib/office_graph/agent_runtime/adapter_registry.ex`
- Create: `test/support/fixtures/agent_runtime/openspec_review_case.json`
- Test: `test/office_graph/agent_runtime/openspec_review_agent_test.exs`
- Test: `test/office_graph/agent_runtime/no_external_write_test.exs`

**Interfaces:**
- Repository tool reads allowlisted paths at a pinned repository revision and returns hashes plus classified text references.
- OpenSpec tool invokes allowlisted read-only commands `list`, `show`, `status`, and `validate`; it cannot mutate, archive, shell-expand, or accept arbitrary flags.
- Produces deterministic messages, review findings, graph-change proposals, verification checks, and evidence candidates through Task 5's output router.

- [ ] **Step 1: Write the end-to-end acceptance and denial tests**

```elixir
test "OpenSpec review produces governed records from authorized context", context do
  assert {:ok, execution} = invoke_openspec_review(context)
  assert :ok = perform_all_agent_jobs(execution.id)

  completed = execution_with_outputs!(execution.id)
  assert completed.state == "completed"
  assert Enum.any?(completed.outputs, &(&1.kind == "message"))
  assert Enum.any?(completed.outputs, &(&1.kind == "review_finding_proposal"))
  assert Enum.any?(completed.outputs, &(&1.kind == "evidence_candidate"))
  assert verification_result_count(context.run.id) == 0
end

test "the first agent has no external-write or arbitrary command path" do
  manifest = OpenSpecReview.manifest()
  assert manifest.external_write == false
  assert manifest.tool_keys == ["repository_read", "openspec_read"]
  refute function_exported?(OpenSpecRead, :run, 2)
  refute function_exported?(RepositoryRead, :write, 2)
end
```

- [ ] **Step 2: Run acceptance tests and observe missing tools/workflow**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/openspec_review_agent_test.exs test/office_graph/agent_runtime/no_external_write_test.exs`

Expected: FAIL because the read-only tools and canonical workflow are absent.

- [ ] **Step 3: Implement allowlisted read-only tools**

```elixir
@commands %{
  "list" => ["openspec", "list", "--json"],
  "show" => ["openspec", "show"],
  "status" => ["openspec", "status", "--change"],
  "validate" => ["openspec", "validate", "--strict"]
}

def invoke(%ToolInput{action: action, arguments: arguments} = input) do
  with {:ok, base_argv} <- Map.fetch(@commands, action),
       {:ok, argv} <- validate_arguments(action, base_argv, arguments),
       {:ok, result} <- runner().run(argv, input.timeout_ms) do
    classify_read_output(input.request_id, action, result)
  else
    :error -> {:error, {:terminal, :unsupported_openspec_action}}
    {:error, reason} -> AdapterResult.normalize({:error, reason})
  end
end
```

The repository tool canonicalizes paths, requires they remain under the configured repo root, checks an allowlist, caps byte count, reads only the pinned revision, and returns content hash plus typed classification. The test runner is deterministic and does not spawn a shell.

- [ ] **Step 4: Implement the canonical workflow over typed steps**

```elixir
@steps [
  %{key: "context:repository", adapter: "repository_read"},
  %{key: "context:openspec", adapter: "openspec_read"},
  %{key: "model:review", adapter: "deterministic_review"},
  %{key: "output:route", adapter: "internal_output_router"}
]

def steps, do: @steps
```

Create each step through the durable state machine. Pass only context-entry references and hashes between steps, validate final structured output against the declared schema, and route each accepted output through the allowlist. GitHub resources and schemas must not be required by these modules.

- [ ] **Step 5: Verify end-to-end records and boundary isolation**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime/openspec_review_agent_test.exs test/office_graph/agent_runtime/no_external_write_test.exs test/office_graph/architecture`

Expected: PASS with proposals/evidence candidates but no verification result or external write.

Run: `rg -n "GitHub|github" lib/office_graph/agent_runtime`

Expected: no output.

- [ ] **Step 6: Commit the first agent**

```bash
git add lib/office_graph/agent_runtime test/office_graph/agent_runtime test/support/fixtures/agent_runtime
git commit -m "feat: add deterministic openspec review agent"
```

### Task 8: Verify, Synchronize, And Archive

**Files:**
- Modify: `openspec/changes/implement-internal-agent-runtime/tasks.md`
- Modify: `openspec/specs/agent-definitions/spec.md`
- Modify: `openspec/specs/agent-context-packages/spec.md`
- Modify: `openspec/specs/agent-tool-adapters/spec.md`
- Modify: `openspec/specs/agent-approval-requests/spec.md`
- Modify: `openspec/specs/agent-runtime/spec.md`
- Modify: `openspec/specs/agent-executions/spec.md`
- Modify: `openspec/specs/node-conversations/spec.md`
- Modify: `openspec/specs/work-runs/spec.md`
- Modify: `openspec/specs/verification-evidence/spec.md`
- Modify: `openspec/specs/operator-console/spec.md`
- Move: `openspec/changes/implement-internal-agent-runtime/` to `openspec/changes/archive/2026-07-13-implement-internal-agent-runtime/`
- Move: `docs/superpowers/plans/2026-07-13-internal-agent-runtime.md` to `docs/superpowers/plans/archive/2026-07-13-internal-agent-runtime.md`
- Modify: `docs/superpowers/plans/README.md`

**Interfaces:**
- Produces: archived AgentRuntime contracts ready for the final end-to-end feature-completion change without identity/governance expansion.

- [ ] **Step 1: Run the complete deterministic runtime slice**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/agent_runtime test/office_graph/node_conversations test/office_graph/proposed_changes test/office_graph/verification test/office_graph/work_packets/work_run_contracts_test.exs test/office_graph/work_packets/work_run_evidence_test.exs test/office_graph/projections/agent_execution_test.exs test/office_graph_web/agent_commands_api_test.exs test/office_graph_web/agent_conversation_graphql_test.exs test/office_graph/architecture`

Expected: PASS with deterministic adapters and no hosted credentials.

- [ ] **Step 2: Run frontend and strict OpenSpec validation**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'cd assets && pnpm relay:check && pnpm vitest run app/routes/operator && pnpm typecheck && pnpm lint && pnpm build'`

Expected: every frontend gate passes.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate implement-internal-agent-runtime --strict`

Expected: `Change 'implement-internal-agent-runtime' is valid`.

- [ ] **Step 3: Run the canonical repository gate and whitespace check**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix verify`

Expected: all backend, frontend, architecture, advisory, and OpenSpec gates pass.

Run: `git diff --check`

Expected: no output.

- [ ] **Step 4: Verify requirements and archive the completed change**

Update each task checkbox only after implementation evidence exists. Map every requirement scenario to a focused test, then run:

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec archive implement-internal-agent-runtime --yes`

Expected: delta specs merge into canonical specs and the change moves to `openspec/changes/archive/2026-07-13-implement-internal-agent-runtime/`.

- [ ] **Step 5: Revalidate and commit the archive**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --all --strict`

Expected: every spec and active change validates.

```bash
git add openspec docs/superpowers/plans
git commit -m "chore: archive internal agent runtime"
```
