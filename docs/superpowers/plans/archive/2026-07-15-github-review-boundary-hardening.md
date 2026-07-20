# GitHub Review Boundary Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the six current PR review findings by enforcing exact health-read scope, persisting installation revocation, preserving review-reply payloads, surfacing permission remediation, and retrying transient worker storage reads.

**Architecture:** Authorization will use the installation's governing scope as the requested policy scope. Reconciliation will retain the already-authorized installation through provider failure handling so a revocation and its terminal outcome commit together. Outbound payload validation will validate a nonblank body without normalizing it. Worker resource access will pass through a narrow configurable loader so storage errors are retryable while missing, revoked, or cross-scope records remain terminal.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash, Ecto/Postgres, Oban, ExUnit, OpenSpec 1.4.1, project Nix flake.

## Global Constraints

- Run every project runtime and CLI command inside the project Nix flake.
- Update canonical and archived OpenSpec scenarios together.
- Preserve non-enumerating authorization behavior and fixed Oban retry budgets.
- Add behavior regressions first and observe each one fail for the reported reason.
- Keep each root-cause cluster independently testable and committed.

---

### Task 1: Authorize Health At The Installation Scope And Remediate Permission Denials

**Files:**
- Modify: `test/office_graph/projections/integration_health_test.exs`
- Modify: `lib/office_graph/github_integration/health.ex`
- Modify: `openspec/specs/integration-health/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/integration-health/spec.md`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`

**Interfaces:**
- Consumes: `Authorization.authorize_projection/3`, `Installation.workspace_id`, and safe failure summaries.
- Produces: health reads authorized against the exact target workspace or organization scope, plus `reauthorize_installation` for `permission_denied`.

- [x] **Step 1: Write failing health regressions**

Import `OfficeGraph.SessionCaseHelpers`, bind an organization-scoped installation with an organization-scoped owner, then read it with a second session that has `skeleton.read` only in the current workspace:

```elixir
test "organization-scoped health requires organization-scoped read authority" do
  {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
  grant_organization_role_assignment!(bootstrap)

  {:ok, bound} =
    GitHubIntegration.bind_installation(bootstrap.session, %{
      idempotency_key: "bind-health-organization-scope",
      external_installation_id: System.unique_integer([:positive]),
      workspace_id: nil,
      app_slug: "office-graph",
      account_login: "Un3qual",
      account_type: "organization",
      service_principal_email: "github-service-health-org@office-graph.local",
      webhook_principal_email: "github-webhook-health-org@office-graph.local",
      webhook_secret_reference: "test-secret://github/health/org/webhook",
      app_private_key_reference: "test-secret://github/health/org/private-key",
      permissions: [
        %{name: "checks", access_level: "write"},
        %{name: "pull_requests", access_level: "write"}
      ]
    })

  workspace_reader =
    create_session_with_capabilities!(bootstrap, ["skeleton.read"],
      prefix: "github-health-workspace-reader"
    )

  assert {:error, :forbidden} =
           Projections.integration_health(workspace_reader, bound.installation.id)
end
```

Extend the existing provider-permission-denial test to read health and require reauthorization:

```elixir
assert {:ok, health} =
         GitHubIntegration.integration_health(context.session, context.installation.id)

assert health.remediation_code == "reauthorize_installation"
```

- [x] **Step 2: Run RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/projections/integration_health_test.exs test/office_graph/github_integration/outbound_commands_test.exs'
```

Expected: the workspace-only reader receives organization health, and the permission-denied health view has no remediation.

- [x] **Step 3: Implement target-scope authorization and remediation**

Load and tenant-check the installation before policy evaluation, then authorize the exact target scope:

```elixir
with {:ok, installation} <- scoped_installation(session_context, installation_id),
     :ok <-
       Authorization.authorize_projection(session_context, :skeleton_read,
         organization_id: installation.organization_id,
         workspace_id: installation.workspace_id
       ) do
  # existing bounded assembly
end
```

The scope helper must accept only the same organization and either the current workspace or an organization-scoped row; the authorization call, not that structural guard, decides whether an organization row is readable. Add `permission_denied` beside `installation_revoked` in the reauthorization failure condition.

- [x] **Step 4: Update both health and GitHub OpenSpec copies**

Add scenarios stating that workspace-only authority cannot read organization-scoped health and that provider permission denial produces installation-reauthorization remediation.

- [x] **Step 5: Run GREEN and commit**

Run the Step 2 command, then:

```bash
git add lib/office_graph/github_integration/health.ex test/office_graph/projections/integration_health_test.exs test/office_graph/github_integration/outbound_commands_test.exs openspec/specs/integration-health/spec.md openspec/changes/archive/2026-07-14-add-github-review-integration/specs/integration-health/spec.md openspec/specs/github-review-integration/spec.md openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md
git commit -m "fix: enforce GitHub health authority"
```

### Task 2: Persist Provider-Reported Installation Revocation

**Files:**
- Modify: `test/office_graph/github_integration/reconciliation_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`

**Interfaces:**
- Consumes: the installation already authorized by `reconcile_provider/2` and `Installation.set_lifecycle`.
- Produces: one transaction that records the terminal outcome and sets lifecycle to `revoked` for `installation_revoked`.

- [x] **Step 1: Write the failing lifecycle regression**

After the existing provider response `{:error, :installation_revoked}`, assert:

```elixir
installation =
  Ash.get!(OfficeGraph.GitHubIntegration.Installation, context.installation.id,
    authorize?: false
  )

assert installation.lifecycle_state == "revoked"
```

- [x] **Step 2: Run RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/github_integration/reconciliation_test.exs'
```

Expected: the terminal outcome exists but the installation remains `active`.

- [x] **Step 3: Retain installation context through failure handling**

Split authorization from the provider pipeline so provider failures receive the already-authorized installation:

```elixir
defp reconcile_provider(operation, request) do
  with {:ok, installation} <- authorized_installation(operation, request) do
    reconcile_provider(operation, request, installation)
  end
end

defp reconcile_provider(operation, request, installation) do
  with {:ok, credential} <- resolve_credential(operation, installation),
       {:ok, source} <- Integrations.ensure_provider_source("github", "GitHub"),
       {:ok, snapshot} <- fetch_snapshot(request, installation, credential) do
    reconcile_snapshot(operation, request, installation, source, snapshot)
  else
    {:error, {:provider, reason}} -> record_failure(operation, request, installation, reason)
    {:error, _error} = error -> error
  end
end
```

Inside the existing outcome transaction, update lifecycle through `:set_lifecycle` only when the classified code is `:installation_revoked`, then persist the terminal outcome. Do not re-fetch through the active-only authorization path after revocation.

- [x] **Step 4: Update both GitHub OpenSpec copies**

Strengthen the revocation scenario so a provider-reported revocation persists the revoked lifecycle before later webhook or outbound gates run.

- [x] **Step 5: Run GREEN and commit**

Run the Step 2 command, then:

```bash
git add lib/office_graph/github_integration/reconciler.ex test/office_graph/github_integration/reconciliation_test.exs openspec/specs/github-review-integration/spec.md openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md
git commit -m "fix: persist revoked GitHub installations"
```

### Task 3: Preserve Review Reply Whitespace

**Files:**
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`
- Modify: `lib/office_graph/github_integration/outbound_commands.ex`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`

**Interfaces:**
- Consumes: the web parser's existing raw-string contract.
- Produces: `required_raw_string/2`, which rejects blank bodies but returns the original nonblank binary.

- [x] **Step 1: Write the failing payload-fidelity regression**

Add a direct command/worker behavior test:

```elixir
test "review replies preserve intentional body whitespace", context do
  body = "\n    indented code\n"
  attrs = reply_attrs(context, body)
  operation = command_operation!(context, :github_review_reply, "reply:whitespace", attrs)

  assert {:ok, action} = OutboundCommands.reply_to_review(context.session, operation, attrs)
  assert action.input["body"] == body

  Provider.put(%{
    {"review_reply", "PRRC_outbound"} => {:ok, %{id: "reply-whitespace", version: "v1"}}
  })

  assert :ok = OutboundWorker.perform(job_for(action.id))
  assert Provider.request("review_reply", "PRRC_outbound").body == body
end
```

- [x] **Step 2: Run RED**

Run the outbound command test file. Expected: the persisted and provider body is trimmed.

- [x] **Step 3: Validate without normalizing**

Use `required_raw_string(attrs, :body)` in `normalize_reply/1`:

```elixir
defp required_raw_string(attrs, key) do
  case fetch(attrs, key) do
    value when is_binary(value) ->
      if String.trim(value) == "",
        do: {:error, {:invalid_field, key}},
        else: {:ok, value}

    _invalid ->
      {:error, {:invalid_field, key}}
  end
end
```

Keep `required_string/2` for identifiers, versions, URLs, and enumerated values.

- [x] **Step 4: Update both GitHub OpenSpec copies**

Add a scenario requiring exact preservation of nonblank Markdown reply payloads.

- [x] **Step 5: Run GREEN and commit**

Run the outbound test file, then commit the command, regression, and two spec copies with `fix: preserve GitHub reply payloads`.

### Task 4: Retry Transient Worker Record Reads

**Files:**
- Create: `lib/office_graph/github_integration/record_loader.ex`
- Create: `test/support/office_graph/github_record_loader_test_adapter.ex`
- Modify: `config/config.exs`
- Modify: `test/office_graph/github_integration/webhook_worker_test.exs`
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`
- Modify: `lib/office_graph/github_integration/webhook_worker.ex`
- Modify: `lib/office_graph/github_integration/outbound_worker.ex`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`

**Interfaces:**
- Produces: `RecordLoader.get/3` backed by `RecordLoader.AshAdapter`, configurable as `:github_record_loader`.
- Produces: retryable safe code `integration_storage_unavailable` for valid worker jobs whose record read fails.

- [x] **Step 1: Add the test loader and failing worker regressions**

The test adapter stores per-resource responses in ETS and delegates when no response is configured:

```elixir
@table __MODULE__

def put(responses) when is_map(responses) do
  ensure_table!()
  :ets.delete_all_objects(@table)
  :ets.insert(@table, Enum.to_list(responses))
  :ok
end

def get(resource, id, opts) do
  ensure_table!()

  case :ets.lookup(@table, resource) do
    [{^resource, response}] -> response
    [] -> Ash.get(resource, id, opts)
  end
end

defp ensure_table! do
  case :ets.whereis(@table) do
    :undefined ->
      try do
        :ets.new(@table, [:named_table, :public, :set])
      rescue
        ArgumentError -> @table
      end

    table ->
      table
  end
end
```

For the webhook worker, configure `Installation => {:error, :database_unavailable}` and assert:

```elixir
assert {:error, "integration_storage_unavailable"} = WebhookWorker.perform(job)
assert Repo.get!(Oban.Job, job.id).meta == %{}
```

For the outbound worker, configure `OutboundAction => {:error, :database_unavailable}` and assert the same retry result, that the action remains `pending`, and that terminal metadata is absent.

- [x] **Step 2: Run RED**

Run the webhook worker and outbound command test files. Expected: both workers return terminal cancellations under the current catch-all branches.

- [x] **Step 3: Add the production loader boundary**

```elixir
defmodule OfficeGraph.GitHubIntegration.RecordLoader do
  @callback get(module(), term(), keyword()) :: {:ok, struct() | nil} | {:error, term()}

  def get(resource, id, opts) do
    implementation().get(resource, id, opts)
  end

  defp implementation do
    Application.fetch_env!(:office_graph, :github_record_loader)
  end
end

defmodule OfficeGraph.GitHubIntegration.RecordLoader.AshAdapter do
  @behaviour OfficeGraph.GitHubIntegration.RecordLoader
  def get(resource, id, opts), do: Ash.get(resource, id, opts)
end
```

Configure the Ash adapter by default. Route worker `Ash.get/3` calls through the loader. Distinguish results explicitly:

```elixir
{:ok, matching_record} -> {:ok, matching_record}
{:ok, _missing_or_cross_scope} -> {:error, terminal_code}
{:error, _storage_error} -> {:error, :integration_storage_unavailable}
```

In initial worker lookup branches, normalize `integration_storage_unavailable` through `DurableDelivery.normalize_worker_result/2` with the fixed ten-attempt budget and do not stage terminal metadata. In the outbound action pipeline, classify that code as retryable. Split `Ash.read_one/2` errors in credential-binding helpers the same way so the same root cause cannot recur one lookup later.

- [x] **Step 4: Update both GitHub OpenSpec copies**

Add a scenario stating that transient installation, outbound-action, target, or credential record-read failures retry without being classified as revoked, invalid, or terminal.

- [x] **Step 5: Run GREEN and commit**

Run the two focused files, then commit the loader, workers, tests, config, and two spec copies with `fix: retry GitHub worker storage reads`.

### Task 5: Verify, Archive, Push, And Reply

- [x] **Step 1: Run focused integration verification**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/projections/integration_health_test.exs test/office_graph/github_integration/reconciliation_test.exs test/office_graph/github_integration/outbound_commands_test.exs test/office_graph/github_integration/webhook_worker_test.exs'
```

- [x] **Step 2: Run repository verification**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix format --check-formatted && openspec validate --specs --strict && mix verify && git diff --check'
```

- [x] **Step 3: Archive and commit this completed plan**

Move this file to `docs/superpowers/plans/archive/2026-07-15-github-review-boundary-hardening.md`, mark all checkboxes complete, and commit the documentation.

- [x] **Step 4: Push once and reply from the cached snapshot**

Push `codex/github-review-integration` once. Reply to the six cached thread IDs with the root-cause fix, commit, and verification evidence. Do not fetch PR state again after the push.
