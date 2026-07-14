# GitHub Review Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingest GitHub review and check activity into provider-neutral Office Graph records, then support narrow authorized replies/check updates with durable replay and safe health reporting.

**Architecture:** A verified GitHub webhook creates an authenticated system operation, retains the valid raw body, and enqueues a unique reconciliation job. Reconciliation reads authoritative GitHub state through an adapter, upserts provider-neutral SoftwareProving resources plus GitHub extensions, and emits typed relationships/signals; explicit outbound commands are the only path to provider writes.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix 1.8, Ash 3, AshPostgres, Ecto/Postgres, Oban 2.x, Req, Plug.Crypto, ExUnit, Bypass, OpenSpec, Nix.

## Global Constraints

- Enter the project Nix flake for every runtime and CLI command.
- Implement only after `implement-typed-graph-relationships` is archived or present in the branch ancestry.
- Treat `openspec/changes/add-github-review-integration/` as the behavioral source of truth.
- Keep shared Operations, DurableDelivery, SoftwareProving, and WorkGraph contracts free of GitHub names and payload shapes.
- Never persist secret values in Ash resources, logs, job args, audit metadata, GraphQL, or JSON API output.
- Permit only review replies and status/check updates; commits, branch writes, merges, code execution, and general GitHub automation stay unavailable.
- Normal tests and `mix verify` must use deterministic adapters and never require live GitHub.
- Add backend service/webhook principals and credential metadata only; human identity/governance administration remains deferred.

---

### Task 1: Generic System Operations And Durable Events

**Files:**
- Create: `priv/repo/migrations/20260713110000_add_system_operation_contract.exs`
- Create: `lib/office_graph/operations/system_operation_request.ex`
- Create: `lib/office_graph/durable_delivery/system_event_request.ex`
- Create: `lib/office_graph/durable_delivery/system_conformance_worker.ex`
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph/operations/operation_correlation.ex`
- Modify: `lib/office_graph/durable_delivery.ex`
- Modify: `lib/office_graph/durable_delivery/domain_event.ex`
- Modify: `lib/office_graph/durable_delivery/projection_invalidation.ex`
- Modify: `lib/office_graph/durable_delivery/subscriptions.ex`
- Test: `test/office_graph/operations/system_operations_test.exs`
- Test: `test/office_graph/durable_delivery/system_event_test.exs`
- Test: `test/office_graph/durable_delivery/system_conformance_worker_test.exs`

**Interfaces:**
- Produces: `Operations.start_system_operation(%SystemOperationRequest{}) :: {:ok, OperationCorrelation.t()} | {:error, term()}`.
- Produces: `DurableDelivery.record_and_enqueue_system(operation, attrs) :: {:ok, DomainEvent.t()} | {:error, term()}`.
- `SystemOperationRequest.new/1` requires `principal_id`, `organization_id`, `action`, `system_kind`, `authority_basis`, `idempotency_scope`, and `idempotency_key`; accepts `workspace_id`, `credential_id`, `causation_operation_id`, `subject_kind`, `subject_id`, and `subject_version` only as declared by the system-kind policy.
- Human `start_operation/3`, `start_command/4`, and `EventRequest.new/3` retain their current session, workspace, subject, and version requirements.

- [ ] **Step 1: Write the fail-closed system-operation tests**

```elixir
test "organization-scoped system work has explicit authority and no human session", context do
  assert {:ok, request} =
           SystemOperationRequest.new(%{
             principal_id: context.webhook_principal.id,
             organization_id: context.organization.id,
             action: "provider.webhook.receive",
             system_kind: "provider_webhook",
             authority_basis: "installation_binding",
             credential_id: context.credential.id,
             idempotency_scope: "github_delivery",
             idempotency_key: "delivery-123"
           })

  assert {:ok, operation} = Operations.start_system_operation(request)
  assert operation.authority_kind == "system"
  assert operation.session_id == nil
  assert operation.workspace_id == nil
end

test "human constructors still reject missing session and workspace", context do
  invalid = %{context.session | session_id: nil, workspace_id: nil}
  assert {:error, :forbidden} = Operations.start_operation(invalid, :manual_intake_submit)
end

test "undeclared nullable system fields fail closed", context do
  assert {:error, {:invalid_system_scope, "provider_reconcile"}} =
           SystemOperationRequest.new(%{
             principal_id: context.principal.id,
             organization_id: context.organization.id,
             action: "integration.reconcile",
             system_kind: "provider_reconcile",
             authority_basis: "installation_binding",
             idempotency_scope: "provider_object",
             idempotency_key: "pr-44"
           })
end
```

- [ ] **Step 2: Run the focused tests and observe missing system contracts**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/operations/system_operations_test.exs test/office_graph/durable_delivery/system_event_test.exs test/office_graph/durable_delivery/system_conformance_worker_test.exs`

Expected: FAIL because system requests, nullable constraints, and conformance worker do not exist.

- [ ] **Step 3: Implement a separate constructor and constrained persistence**

```elixir
defmodule OfficeGraph.Operations.SystemOperationRequest do
  @enforce_keys [
    :principal_id,
    :organization_id,
    :action,
    :system_kind,
    :authority_basis,
    :idempotency_scope,
    :idempotency_key
  ]
  defstruct @enforce_keys ++ [
              :workspace_id,
              :credential_id,
              :causation_operation_id,
              :subject_kind,
              :subject_id,
              :subject_version
            ]

  @organization_scoped_kinds MapSet.new(["provider_webhook", "agent_maintenance"])

  def new(attrs) when is_map(attrs) do
    with {:ok, request} <- cast_required(attrs),
         :ok <- validate_declared_scope(request),
         :ok <- validate_subject_tuple(request) do
      {:ok, request}
    end
  end

  def organization_scoped?(kind), do: MapSet.member?(@organization_scoped_kinds, kind)
end
```

Add an `authority_kind` discriminator plus nullable system-only columns and database checks: human rows require principal/session/workspace; system rows require principal/system kind/authority/idempotency scope and follow the declared workspace/subject tuple policy. Use separate partial unique indexes for human and system replay.

- [ ] **Step 4: Add the non-GitHub conformance worker and system event path**

```elixir
defmodule OfficeGraph.DurableDelivery.SystemConformanceWorker do
  use Oban.Worker, queue: :delivery, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    OfficeGraph.DurableDelivery.dispatch(event_id)
  end
end
```

`record_and_enqueue_system/2` must validate the system operation, require a typed event key/kind, permit nil workspace/subject data only for declared kinds, and publish organization-scoped invalidations only to authorized organization subscribers.

- [ ] **Step 5: Run system-operation, durable-delivery, and human regression tests**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/operations_test.exs test/office_graph/operations/system_operations_test.exs test/office_graph/durable_delivery test/office_graph/integrations/manual_intake_replay_test.exs`

Expected: PASS; existing human events retain required workspace and subject version.

- [ ] **Step 6: Commit the shared foundation**

```bash
git add priv/repo/migrations/20260713110000_add_system_operation_contract.exs lib/office_graph/operations.ex lib/office_graph/operations lib/office_graph/durable_delivery.ex lib/office_graph/durable_delivery test/office_graph/operations test/office_graph/durable_delivery
git commit -m "feat: add authenticated system operations"
```

### Task 2: Provider-Neutral Software Resources

**Files:**
- Create: `priv/repo/migrations/20260713111000_create_software_proving_resources.exs`
- Modify: `lib/office_graph/software_proving.ex`
- Create: `lib/office_graph/software_proving/domain.ex`
- Create: `lib/office_graph/software_proving/repository.ex`
- Create: `lib/office_graph/software_proving/repository_ref.ex`
- Create: `lib/office_graph/software_proving/commit.ex`
- Create: `lib/office_graph/software_proving/pull_request.ex`
- Create: `lib/office_graph/software_proving/review_thread.ex`
- Create: `lib/office_graph/software_proving/review_comment.ex`
- Create: `lib/office_graph/software_proving/check_run.ex`
- Create: `lib/office_graph/integrations/github/repository_extension.ex`
- Create: `lib/office_graph/integrations/github/pull_request_extension.ex`
- Create: `lib/office_graph/integrations/github/check_run_extension.ex`
- Modify: `lib/office_graph/external_refs.ex`
- Test: `test/office_graph/software_proving/resource_contracts_test.exs`
- Test: `test/office_graph/integrations/github/extension_separation_test.exs`

**Interfaces:**
- Produces: provider-neutral records keyed by organization, governing workspace, provider source, stable external reference, provider version, lifecycle, and parent object identities.
- Produces: private idempotent upsert functions such as `SoftwareProving.upsert_pull_request(system_operation, attrs) :: {:ok, PullRequest.t()} | {:error, term()}`.
- GitHub extension resources contain GitHub-only identifiers and state; provider-neutral resources contain no installation ID, GraphQL node ID, delivery ID, or GitHub enum.

- [ ] **Step 1: Write resource ownership and provider-neutrality tests**

```elixir
test "pull requests retain provider-neutral identity and lifecycle", context do
  attrs = %{
    repository_id: context.repository.id,
    external_reference_id: context.external_reference.id,
    provider_version: "sha:abc123",
    number: 44,
    title: "Harden reconciliation",
    lifecycle: "open"
  }

  assert {:ok, pull_request} = SoftwareProving.upsert_pull_request(context.operation, attrs)
  assert pull_request.organization_id == context.operation.organization_id
  assert pull_request.workspace_id == context.operation.workspace_id
  refute Map.has_key?(Map.from_struct(pull_request), :github_node_id)
  refute Map.has_key?(Map.from_struct(pull_request), :installation_id)
end

test "the same provider object cannot cross organizations", context do
  assert {:error, :forbidden} =
           SoftwareProving.upsert_pull_request(
             context.other_organization_operation,
             context.organization_pull_request_attrs
           )
end

test "a native pull request uses the same base resource without provider fiction", context do
  attrs = %{
    repository_id: context.native_repository.id,
    external_reference_id: nil,
    provider_version: nil,
    number: 7,
    title: "Office Graph review",
    lifecycle: "open"
  }

  assert {:ok, pull_request} = SoftwareProving.create_native_pull_request(context.operation, attrs)
  assert pull_request.external_source_id == nil
  assert pull_request.provider_object_type == nil
end
```

- [ ] **Step 2: Run resource tests and observe absent SoftwareProving domain**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/software_proving/resource_contracts_test.exs test/office_graph/integrations/github/extension_separation_test.exs`

Expected: FAIL because the resources and upsert boundary are absent.

- [ ] **Step 3: Add focused Ash resources and system-operation upserts**

```elixir
def upsert_pull_request(operation, attrs) do
  with :ok <- Operations.validate_system_operation(operation, "provider_reconcile"),
       :ok <- validate_parent_scope(operation, attrs.repository_id) do
    PullRequest
    |> Ash.Changeset.for_create(:upsert_from_provider, scoped_attrs(operation, attrs))
    |> Ash.create(authorize?: false, upsert?: true, upsert_identity: :provider_object)
  end
end
```

Give every resource explicit lifecycle/provider-version checks and composite identities scoped to organization and provider source. Add foreign keys and lookup indexes for repository/ref/commit/PR/thread/comment/check hierarchy. Register only read routes required by approved projections; provider writes stay private.

- [ ] **Step 4: Verify resources, migrations, and architecture inventories**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix ecto.reset`

Expected: PASS.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/software_proving test/office_graph/integrations/github/extension_separation_test.exs test/office_graph/architecture`

Expected: PASS with GitHub-only fields isolated to extension resources.

- [ ] **Step 5: Commit provider-neutral persistence**

```bash
git add priv/repo/migrations/20260713111000_create_software_proving_resources.exs lib/office_graph/software_proving.ex lib/office_graph/software_proving lib/office_graph/integrations/github lib/office_graph/external_refs.ex test/office_graph/software_proving test/office_graph/integrations/github/extension_separation_test.exs test/office_graph/architecture
git commit -m "feat: add provider neutral software resources"
```

### Task 3: Installation Binding, Principals, And Secret References

**Files:**
- Create: `priv/repo/migrations/20260713112000_create_github_installation_bindings.exs`
- Create: `lib/office_graph/integrations/github/installation_binding.ex`
- Create: `lib/office_graph/integrations/github/commands.ex`
- Create: `lib/office_graph/integrations/github/secret_store.ex`
- Create: `lib/office_graph/integrations/github/secret_store/test.ex`
- Create: `lib/office_graph/integrations/github/secret_store/environment.ex`
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph/identity/credential.ex`
- Modify: `lib/office_graph/foundation/bootstrap.ex`
- Modify: `lib/office_graph_web/graphql/operator_commands/mutations.ex`
- Create: `lib/office_graph_web/graphql/operator_commands/resolvers/github.ex`
- Create: `lib/office_graph_web/json_api/operator_commands/github_controller.ex`
- Modify: `lib/office_graph_web/router.ex`
- Modify: `config/config.exs`
- Modify: `config/dev.exs`
- Modify: `config/test.exs`
- Test: `test/office_graph/integrations/github/installation_binding_test.exs`
- Test: `test/office_graph/integrations/github/secret_store_test.exs`
- Test: `test/office_graph_web/github_installation_commands_test.exs`

**Interfaces:**
- Produces: `GitHub.Commands.bind_installation(session, operation, attrs) :: {:ok, InstallationBinding.t()} | {:error, term()}`.
- `attrs` requires `installation_id`, `organization_id`, `service_principal_id`, `webhook_principal_id`, `webhook_credential_id`, `app_private_key_credential_id`, and a normalized permission snapshot; accepts `workspace_id`.
- Produces: `GitHub.SecretStore.fetch(credential, purpose) :: {:ok, binary()} | {:error, :unavailable | :forbidden}`.
- Produces human command action keys `github.installation.bind`, `github.review.reply`, and `github.check.update`; no repository-write action key is registered.

- [ ] **Step 1: Write binding, authorization, and non-disclosure tests**

```elixir
test "local owner binds an installation without persisting secret material", context do
  assert {:ok, binding} =
           GitHub.Commands.bind_installation(context.session, context.operation, %{
             installation_id: 9001,
             organization_id: context.organization.id,
             workspace_id: context.workspace.id,
             service_principal_id: context.service_principal.id,
             webhook_principal_id: context.webhook_principal.id,
             webhook_credential_id: context.webhook_credential.id,
             app_private_key_credential_id: context.private_key_credential.id,
             permissions: %{"checks" => "write", "pull_requests" => "write"}
           })

  assert binding.installation_id == 9001
  refute inspect(binding) =~ context.webhook_secret
  refute Jason.encode!(binding) =~ context.private_key
end

test "cross-tenant and underprivileged bindings fail closed", context do
  assert {:error, :forbidden} =
           GitHub.Commands.bind_installation(
             context.session,
             context.operation,
             context.other_organization_attrs
           )
end

test "unauthenticated installation setup is rejected before command creation", context do
  conn = post(build_conn(), "/api/v1/commands/bind-github-installation", context.valid_body)
  assert conn.status == 401
  assert operation_count("github.installation.bind") == 0
end
```

- [ ] **Step 2: Run binding and secret tests and observe missing implementation**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/installation_binding_test.exs test/office_graph/integrations/github/secret_store_test.exs test/office_graph_web/github_installation_commands_test.exs`

Expected: FAIL because installation binding and secret adapters are absent.

- [ ] **Step 3: Implement narrow secret resolution and binding transaction**

```elixir
defmodule OfficeGraph.Integrations.GitHub.SecretStore do
  @callback fetch(OfficeGraph.Identity.Credential.t(), atom()) ::
              {:ok, binary()} | {:error, :unavailable | :forbidden}

  def fetch(credential, purpose) do
    adapter().fetch(credential, purpose)
  end

  defp adapter do
    Application.fetch_env!(:office_graph, :github_secret_store)
  end
end
```

The test adapter resolves from process-owned fixture state; the development adapter maps a credential reference to an explicitly configured environment variable name. Neither adapter accepts a secret value from API input. The binding command validates owner authority, credential purpose/scope/lifecycle, principal kind, installation uniqueness, and permissions before one transaction writes the binding and trace records.

- [ ] **Step 4: Verify transports return only safe metadata**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/installation_binding_test.exs test/office_graph/integrations/github/secret_store_test.exs test/office_graph_web/github_installation_commands_test.exs test/office_graph/foundation/bootstrap_test.exs`

Expected: PASS, and response bodies contain credential references but no secret bytes.

- [ ] **Step 5: Commit installation and secret handling**

```bash
git add priv/repo/migrations/20260713112000_create_github_installation_bindings.exs lib/office_graph/integrations/github lib/office_graph/identity/credential.ex lib/office_graph/operations.ex lib/office_graph/foundation/bootstrap.ex lib/office_graph_web config test/office_graph/integrations/github test/office_graph_web/github_installation_commands_test.exs test/office_graph/foundation/bootstrap_test.exs
git commit -m "feat: bind github app installations"
```

### Task 4: Verified Webhook Receipt

**Files:**
- Create: `lib/office_graph/integrations/github/adapter.ex`
- Create: `lib/office_graph/integrations/github/client.ex`
- Create: `lib/office_graph/integrations/github/webhook_signature.ex`
- Create: `lib/office_graph/integrations/github/webhook_receipt.ex`
- Create: `lib/office_graph/integrations/github/webhook_worker.ex`
- Create: `lib/office_graph_web/controllers/github_webhook_controller.ex`
- Modify: `lib/office_graph_web/endpoint.ex`
- Modify: `lib/office_graph_web/router.ex`
- Modify: `lib/office_graph/raw_archives.ex`
- Test: `test/office_graph/integrations/github/webhook_signature_test.exs`
- Test: `test/office_graph/integrations/github/webhook_receipt_test.exs`
- Test: `test/office_graph_web/github_webhook_controller_test.exs`

**Interfaces:**
- Consumes: exact raw request body plus `x-hub-signature-256`, `x-github-delivery`, and `x-github-event` headers.
- Produces: `GitHub.WebhookReceipt.accept(headers, raw_body) :: {:ok, :accepted | :duplicate} | {:error, :invalid_signature | :unknown_installation | :unsupported_event}`.
- Accepted receipt atomically creates a system operation, raw archive, typed domain event, and unique Oban job keyed by delivery ID.

- [ ] **Step 1: Write signature, duplicate, and pre-archive rejection tests**

```elixir
test "valid deliveries archive once and enqueue once", context do
  headers = signed_headers(context, "delivery-42", "pull_request", context.payload)

  assert {:ok, :accepted} = GitHub.WebhookReceipt.accept(headers, context.payload)
  assert {:ok, :duplicate} = GitHub.WebhookReceipt.accept(headers, context.payload)
  assert count_raw_archives("github_delivery", "delivery-42") == 1
  assert count_oban_jobs(%{"delivery_id" => "delivery-42"}) == 1
end

test "invalid signatures create no operation, archive, event, or job", context do
  headers = Map.put(context.headers, "x-hub-signature-256", "sha256=invalid")
  assert {:error, :invalid_signature} = GitHub.WebhookReceipt.accept(headers, context.payload)
  assert receipt_side_effect_counts() == %{operations: 0, archives: 0, events: 0, jobs: 0}
end

test "unknown installations are rejected before archival", context do
  headers = signed_headers(context, "delivery-43", "pull_request", context.unknown_installation_payload)
  assert {:error, :unknown_installation} =
           GitHub.WebhookReceipt.accept(headers, context.unknown_installation_payload)
  assert receipt_side_effect_counts() == %{operations: 0, archives: 0, events: 0, jobs: 0}
end
```

- [ ] **Step 2: Run webhook tests and observe missing receipt pipeline**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/webhook_signature_test.exs test/office_graph/integrations/github/webhook_receipt_test.exs test/office_graph_web/github_webhook_controller_test.exs`

Expected: FAIL because the signature verifier, raw-body capture, and receipt pipeline are absent.

- [ ] **Step 3: Implement constant-time signature verification and atomic receipt**

```elixir
def verify(raw_body, "sha256=" <> supplied_hex, secret) do
  expected = :crypto.mac(:hmac, :sha256, secret, raw_body)

  with {:ok, supplied} <- Base.decode16(supplied_hex, case: :mixed),
       true <- byte_size(supplied) == byte_size(expected),
       true <- Plug.Crypto.secure_compare(supplied, expected) do
    :ok
  else
    _reason -> {:error, :invalid_signature}
  end
end

def verify(_raw_body, _signature, _secret), do: {:error, :invalid_signature}
```

Capture the body before JSON decoding. Resolve the active installation from signed payload metadata only after verification. Inside one Repo transaction create the system operation, immutable raw archive, domain event, and unique webhook job. Return 202 for accepted/duplicate and stable 401/404/422 responses without adapter or database details.

- [ ] **Step 4: Verify the controller responds promptly without performing reconciliation**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/webhook_signature_test.exs test/office_graph/integrations/github/webhook_receipt_test.exs test/office_graph_web/github_webhook_controller_test.exs`

Expected: PASS; the controller assertion observes no provider read before the 202 response.

- [ ] **Step 5: Commit webhook receipt**

```bash
git add lib/office_graph/integrations/github lib/office_graph_web/controllers/github_webhook_controller.ex lib/office_graph_web/endpoint.ex lib/office_graph_web/router.ex lib/office_graph/raw_archives.ex test/office_graph/integrations/github test/office_graph_web/github_webhook_controller_test.exs
git commit -m "feat: receive verified github webhooks"
```

### Task 5: Authoritative Reconciliation And Product Mapping

**Files:**
- Create: `lib/office_graph/integrations/github/reconciliation_request.ex`
- Create: `lib/office_graph/integrations/github/reconciliation_worker.ex`
- Create: `lib/office_graph/integrations/github/reconciler.ex`
- Create: `lib/office_graph/integrations/github/sync_outcome.ex`
- Create: `lib/office_graph/integrations/github/adapter/test.ex`
- Create: `test/support/fixtures/github/pull_request_opened.json`
- Create: `test/support/fixtures/github/review_submitted.json`
- Create: `test/support/fixtures/github/check_run_completed.json`
- Modify: `lib/office_graph/integrations.ex`
- Modify: `lib/office_graph/external_refs.ex`
- Modify: `lib/office_graph/work_graph.ex`
- Test: `test/office_graph/integrations/github/reconciliation_test.exs`
- Test: `test/office_graph/integrations/github/reconciliation_concurrency_test.exs`
- Test: `test/office_graph/integrations/github/product_mapping_test.exs`

**Interfaces:**
- Adapter produces normalized snapshots `%GitHub.Adapter.PullRequest{}`, `%ReviewThread{}`, `%ReviewComment{}`, and `%CheckRun{}` with stable object ID and provider version.
- Produces: `GitHub.Reconciler.reconcile(system_operation, %ReconciliationRequest{}) :: {:ok, SyncOutcome.t()} | {:error, {:retryable | :terminal, atom()}}`.
- Emits typed relationships through `WorkGraph.create_relationship/3`, signals through existing WorkGraph commands, and external references through `ExternalRefs`; it never writes graph relationship rows directly.
- Reconciliation system operations use generic action `integration.reconcile`, which the typed relationship command recognizes without a GitHub-specific WorkGraph dependency.

- [ ] **Step 1: Write fixture-driven ordering, replay, and rate-limit tests**

```elixir
test "newer provider versions win when deliveries arrive out of order", context do
  configure_snapshot(context.object_id, version: "v2", lifecycle: "merged")
  assert {:ok, first} = Reconciler.reconcile(context.operation_v2, context.request_v2)

  configure_snapshot(context.object_id, version: "v1", lifecycle: "open")
  assert {:ok, stale} = Reconciler.reconcile(context.operation_v1, context.request_v1)

  assert first.state == :reconciled
  assert stale.state == :skipped_stale
  assert pull_request!(context.object_id).lifecycle == "merged"
end

test "rate limits return a bounded retry classification", context do
  configure_adapter_result({:error, {:rate_limited, ~U[2026-07-13 20:00:00Z]}})
  assert {:error, {:retryable, :provider_rate_limited}} =
           Reconciler.reconcile(context.operation, context.request)
end
```

- [ ] **Step 2: Run reconciliation tests and observe absent adapter/reconciler**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/reconciliation_test.exs test/office_graph/integrations/github/reconciliation_concurrency_test.exs test/office_graph/integrations/github/product_mapping_test.exs`

Expected: FAIL because normalized adapter types and reconciliation do not exist.

- [ ] **Step 3: Implement version-locked provider-neutral upserts**

```elixir
def reconcile(operation, request) do
  Repo.transaction(fn ->
    with {:ok, snapshot} <- adapter().fetch(request),
         {:ok, object} <- upsert_if_newer(operation, snapshot),
         :ok <- upsert_external_references(operation, object, snapshot),
         :ok <- map_relationships_and_signals(operation, object, snapshot) do
      record_outcome!(operation, request, object, :reconciled)
    else
      {:skip, :stale} -> record_outcome!(operation, request, nil, :skipped_stale)
      {:error, reason} -> Repo.rollback(classify(reason))
    end
  end)
  |> unwrap_reconciliation()
end
```

Lock on organization/provider/object identity before comparing provider versions. Coalesce jobs by installation/object, batch adapter reads, record received/archived/reconciled/duplicate/skipped/retryable/terminal outcomes, and emit projection invalidations after commit.

- [ ] **Step 4: Verify replay, concurrency, mapping, and query bounds**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/reconciliation_test.exs test/office_graph/integrations/github/reconciliation_concurrency_test.exs test/office_graph/integrations/github/product_mapping_test.exs test/office_graph/work_graph/relationship_queries_test.exs`

Expected: PASS with one canonical record per provider object and no direct graph-edge writes from the adapter.

- [ ] **Step 5: Commit reconciliation**

```bash
git add lib/office_graph/integrations/github lib/office_graph/integrations.ex lib/office_graph/external_refs.ex lib/office_graph/work_graph.ex test/office_graph/integrations/github test/support/fixtures/github
git commit -m "feat: reconcile github review state"
```

### Task 6: Narrow Outbound Commands And Safe Health Projection

**Files:**
- Create: `lib/office_graph/integrations/github/outbound_action.ex`
- Create: `lib/office_graph/integrations/github/outbound_commands.ex`
- Create: `lib/office_graph/integrations/github/outbound_worker.ex`
- Create: `lib/office_graph/integrations/github/health.ex`
- Create: `lib/office_graph/projections/integration_health.ex`
- Modify: `lib/office_graph_web/graphql/operator_commands/mutations.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/queries.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/types.ex`
- Create: `lib/office_graph_web/json_api/operator_commands/github_actions_controller.ex`
- Modify: `lib/office_graph_web/router.ex`
- Test: `test/office_graph/integrations/github/outbound_commands_test.exs`
- Test: `test/office_graph/integrations/github/outbound_worker_test.exs`
- Test: `test/office_graph/projections/integration_health_test.exs`
- Test: `test/office_graph_web/github_actions_api_test.exs`

**Interfaces:**
- Produces: `GitHub.OutboundCommands.reply_to_review(session, operation, attrs)` and `GitHub.OutboundCommands.update_check(session, operation, attrs)`.
- Each command requires installation/object identity, expected provider version, idempotency key, and action-specific typed input.
- Produces: `Projections.integration_health(session, installation_id, limit: 1..50)` with lifecycle, permission/configuration posture, last success, bounded retry/terminal summaries, and safe remediation codes.

- [ ] **Step 1: Write outbound allowlist and replay tests**

```elixir
test "review replies enqueue once and record provider response identity", context do
  attrs = %{
    review_comment_id: context.comment.id,
    body: "Addressed in the proposed change.",
    expected_provider_version: context.comment.provider_version,
    idempotency_key: "reply:comment-9:v1"
  }

  assert {:ok, first} = OutboundCommands.reply_to_review(context.session, context.operation, attrs)
  assert {:ok, replay} = OutboundCommands.reply_to_review(context.session, context.operation, attrs)
  assert replay.id == first.id
  assert count_outbound_jobs(first.id) == 1
end

test "repository writes are not representable", _context do
  refute function_exported?(OutboundCommands, :commit, 3)
  refute function_exported?(OutboundCommands, :merge, 3)
  refute function_exported?(OutboundCommands, :create_branch, 3)
end

test "a revoked installation fails terminally and appears as safe health posture", context do
  revoke_installation!(context.binding)

  assert {:error, {:terminal, :installation_revoked}} =
           perform_outbound_action(context.pending_action)

  assert {:ok, health} = Projections.integration_health(context.session, context.binding.installation_id)
  assert health.lifecycle == "revoked"
  assert health.remediation_code == "reauthorize_installation"
end
```

- [ ] **Step 2: Run outbound and health tests and observe missing commands/projection**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/outbound_commands_test.exs test/office_graph/integrations/github/outbound_worker_test.exs test/office_graph/projections/integration_health_test.exs test/office_graph_web/github_actions_api_test.exs`

Expected: FAIL because the outbound allowlist and health projection are absent.

- [ ] **Step 3: Implement explicit action records and adapter-isolated workers**

```elixir
def reply_to_review(session, operation, attrs) do
  with :ok <- authorize(session, operation, :github_review_reply, attrs),
       {:ok, target} <- load_current_comment(session, attrs.review_comment_id),
       :ok <- require_version(target.provider_version, attrs.expected_provider_version),
       {:ok, binding} <- require_permission(target, "pull_requests", "write") do
    persist_and_enqueue(session, operation, binding, "review_reply", attrs)
  end
end

def update_check(session, operation, attrs) do
  with :ok <- authorize(session, operation, :github_check_update, attrs),
       {:ok, target} <- load_current_check(session, attrs.check_run_id),
       :ok <- require_version(target.provider_version, attrs.expected_provider_version),
       {:ok, binding} <- require_permission(target, "checks", "write") do
    persist_and_enqueue(session, operation, binding, "check_update", attrs)
  end
end
```

The worker resolves credentials at execution time, maps only the two action kinds to adapter calls, records provider response identity/version, and classifies permission, credential, rate-limit, network, and validation failures into stable retry/terminal codes.

- [ ] **Step 4: Implement bounded health reads and transport projections**

```elixir
def integration_health(session, installation_id, opts \\ []) do
  limit = opts |> Keyword.get(:limit, 20) |> min(50) |> max(1)

  with {:ok, binding} <- authorized_binding(session, installation_id),
       {:ok, sync} <- latest_sync_summary(binding, limit),
       {:ok, terminal} <- terminal_summary(binding, limit) do
    {:ok, HealthView.new(binding, sync, terminal)}
  end
end
```

Do not expose raw job args/errors, payloads, exception strings, secret values, or cross-tenant installation existence. Add query-count assertions for the maximum page size.

- [ ] **Step 5: Run outbound, health, transport, and architecture tests**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/integrations/github/outbound_commands_test.exs test/office_graph/integrations/github/outbound_worker_test.exs test/office_graph/projections/integration_health_test.exs test/office_graph_web/github_actions_api_test.exs test/office_graph/architecture`

Expected: PASS with only review reply/check update actions reachable.

- [ ] **Step 6: Commit outbound actions and health**

```bash
git add lib/office_graph/integrations/github lib/office_graph/projections/integration_health.ex lib/office_graph_web test/office_graph/integrations/github test/office_graph/projections/integration_health_test.exs test/office_graph_web/github_actions_api_test.exs test/office_graph/architecture
git commit -m "feat: add github review actions and health"
```

### Task 7: Verify, Synchronize, And Archive

**Files:**
- Modify: `openspec/changes/add-github-review-integration/tasks.md`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/specs/integration-health/spec.md`
- Modify: `openspec/specs/provider-neutral-resources/spec.md`
- Modify: `openspec/specs/durable-work-delivery/spec.md`
- Modify: `openspec/specs/shared-operation-contracts/spec.md`
- Move: `openspec/changes/add-github-review-integration/` to `openspec/changes/archive/2026-07-13-add-github-review-integration/`
- Move: `docs/superpowers/plans/2026-07-13-github-review-integration.md` to `docs/superpowers/plans/archive/2026-07-13-github-review-integration.md`
- Modify: `docs/superpowers/plans/README.md`

**Interfaces:**
- Produces: archived provider/system-operation contracts consumed unchanged by the internal agent runtime.

- [ ] **Step 1: Run the complete deterministic integration slice**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/operations test/office_graph/durable_delivery test/office_graph/software_proving test/office_graph/integrations/github test/office_graph/projections/integration_health_test.exs test/office_graph_web/github_webhook_controller_test.exs test/office_graph_web/github_installation_commands_test.exs test/office_graph_web/github_actions_api_test.exs test/office_graph/architecture`

Expected: PASS with no network access and zero live GitHub credentials.

- [ ] **Step 2: Validate the change and canonical repository gate**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate add-github-review-integration --strict`

Expected: `Change 'add-github-review-integration' is valid`.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix verify`

Expected: all repository gates pass.

Run: `git diff --check`

Expected: no output.

- [ ] **Step 3: Prove generic system-operation reuse before archive**

Run the non-GitHub conformance worker test and inspect shared modules for provider leakage.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/durable_delivery/system_conformance_worker_test.exs`

Expected: PASS.

Run: `rg -n "GitHub|github" lib/office_graph/operations lib/office_graph/durable_delivery lib/office_graph/software_proving`

Expected: no output.

- [ ] **Step 4: Synchronize and archive the completed change**

Update each task checkbox only after implementation evidence exists, then run:

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec archive add-github-review-integration --yes`

Expected: canonical specs are updated and the change moves to `openspec/changes/archive/2026-07-13-add-github-review-integration/`.

- [ ] **Step 5: Revalidate and commit the archive**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --all --strict`

Expected: every spec and active change validates.

```bash
git add openspec docs/superpowers/plans
git commit -m "chore: archive github review integration"
```
