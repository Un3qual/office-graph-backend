# Ash Conformance Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the `first-backend-walking-skeleton` implementation so normal walking-loop domain resources are Ash-backed, and add repeatable conformance gates that prevent future spec-implementation drift of this kind.

**Architecture:** Keep the current Phoenix/Ecto/Postgres walking skeleton behavior, but introduce Ash domains/resources for stable product resources first. Direct Ecto remains allowed only for approved escape hatches: graph identity/relationship writes, idempotency/replay scans, operation/history joins, and bootstrap/maintenance paths that are explicitly documented in an exception ledger. The verification gate gains architecture conformance checks and an evidence matrix before the change can be archived.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix API, Ecto/Postgres, Ash, AshPostgres, AshGraphql, AshJsonApi, Boundary, Absinthe, OpenSpec, Docker Compose Postgres, Nix shell.

---

## File Map

- Create `test/office_graph/architecture/ash_conformance_test.exs` to fail on missing Ash domains/resources and unapproved direct `Repo` mutation paths.
- Create `lib/office_graph/authorization/checks/has_capability.ex` for a reusable Ash policy check that delegates to `OfficeGraph.Authorization.authorize/3`.
- Create `lib/office_graph/work_graph/domain.ex` as the first Ash domain owned by the WorkGraph bounded context.
- Create Ash resources backed by existing tables:
  - `lib/office_graph/work_graph/resources/signal.ex`
  - `lib/office_graph/work_graph/resources/task.ex`
  - `lib/office_graph/work_graph/resources/review_finding.ex`
  - `lib/office_graph/work_graph/resources/verification_check.ex`
  - `lib/office_graph/work_graph/resources/artifact.ex`
  - `lib/office_graph/work_graph/resources/evidence_item.ex`
  - `lib/office_graph/work_graph/resources/verification_result.ex`
- Modify `lib/office_graph/work_graph.ex` so stable typed resource creation and lifecycle transitions call Ash actions. Keep graph identity and relationship writes in explicit Ecto transactions.
- Modify `lib/office_graph/verification.ex` only if needed to pass actor/context through the Ash-backed completion path.
- Modify `lib/office_graph_web/schema.ex` only if the current Absinthe schema must expose Ash-generated GraphQL alongside existing smoke mutations. Do not replace the whole schema in this repair unless the tests require it.
- Modify `.formatter.exs` to import Ash formatters if required by compile/format output.
- Modify `mix.exs` to add `architecture.conformance` to aliases.
- Modify `bin/verify-backend` to run `mix architecture.conformance`.
- Create `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md` to record each remaining direct Ecto path and its approved reason.
- Modify `openspec/changes/first-backend-walking-skeleton/tasks.md` to reopen/add repair tasks instead of leaving the change marked as archive-ready.
- Modify `openspec/changes/first-backend-walking-skeleton/implementation-summary.md` with an evidence matrix mapping requirements to code and gates.

## Task 1: Add A Failing Ash Conformance Test

**Files:**
- Create: `test/office_graph/architecture/ash_conformance_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/office_graph/architecture/ash_conformance_test.exs`:

```elixir
defmodule OfficeGraph.Architecture.AshConformanceTest do
  use ExUnit.Case, async: true

  @ash_domain OfficeGraph.WorkGraph.Domain

  @required_resources [
    OfficeGraph.WorkGraph.Resources.Signal,
    OfficeGraph.WorkGraph.Resources.Task,
    OfficeGraph.WorkGraph.Resources.ReviewFinding,
    OfficeGraph.WorkGraph.Resources.VerificationCheck,
    OfficeGraph.WorkGraph.Resources.Artifact,
    OfficeGraph.WorkGraph.Resources.EvidenceItem,
    OfficeGraph.WorkGraph.Resources.VerificationResult
  ]

  @approved_direct_repo_mutation_files %{
    "lib/office_graph/work_graph.ex" => [
      "graph identity and graph relationship writes stay in one explicit Ecto transaction"
    ],
    "lib/office_graph/integrations.ex" => [
      "raw archive and replay/idempotency storage are approved direct Ecto paths"
    ],
    "lib/office_graph/operations.ex" => [
      "operation correlation creation is the shared operation spine"
    ],
    "lib/office_graph/audit.ex" => [
      "audit append writes are a shared side-effect contract"
    ],
    "lib/office_graph/revisions.ex" => [
      "revision append writes are a shared side-effect contract"
    ],
    "lib/office_graph/identity.ex" => [
      "local bootstrap identity path is accepted for the walking skeleton"
    ],
    "lib/office_graph/tenancy.ex" => [
      "local bootstrap tenancy path is accepted for the walking skeleton"
    ],
    "lib/office_graph/authorization.ex" => [
      "local bootstrap authorization path is accepted for the walking skeleton"
    ],
    "lib/office_graph/proposed_changes.ex" => [
      "proposed-change review ledger is an orchestration table for the skeleton"
    ],
    "lib/office_graph/content.ex" => [
      "rich-text v1 document/block creation remains a narrowed Ecto path until the content domain is Ash-backed"
    ]
  }

  test "work graph has an Ash domain and required Ash resources" do
    assert Code.ensure_loaded?(@ash_domain)

    for resource <- @required_resources do
      assert Code.ensure_loaded?(resource), "#{inspect(resource)} is not loaded"
      assert Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer
    end
  end

  test "work graph Ash domain registers the required resources" do
    assert Code.ensure_loaded?(@ash_domain)

    registered =
      @ash_domain
      |> Ash.Domain.Info.resources()
      |> MapSet.new()

    assert MapSet.subset?(MapSet.new(@required_resources), registered)
  end

  test "direct Repo mutation paths are explicitly allowlisted" do
    repo_mutation_pattern =
      ~r/(Repo\.(insert!?|update!?|delete!?|transaction)\b|Ecto\.Multi\.(insert|update|delete)\b)/

    actual =
      "lib/office_graph"
      |> Path.wildcard("**/*.ex")
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.match?(repo_mutation_pattern)
      end)
      |> Enum.sort()

    assert actual -- Map.keys(@approved_direct_repo_mutation_files) == []
  end
end
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/architecture/ash_conformance_test.exs
```

Expected: fail because `OfficeGraph.WorkGraph.Domain` and `OfficeGraph.WorkGraph.Resources.*` do not exist.

- [ ] **Step 3: Commit the failing architecture test**

Run:

```bash
git add test/office_graph/architecture/ash_conformance_test.exs
git commit -m "test: capture Ash conformance gap"
```

## Task 2: Add The WorkGraph Ash Domain And Resource Set

**Files:**
- Create: `lib/office_graph/work_graph/domain.ex`
- Create: `lib/office_graph/work_graph/resources/signal.ex`
- Create: `lib/office_graph/work_graph/resources/task.ex`
- Create: `lib/office_graph/work_graph/resources/review_finding.ex`
- Create: `lib/office_graph/work_graph/resources/verification_check.ex`
- Create: `lib/office_graph/work_graph/resources/artifact.ex`
- Create: `lib/office_graph/work_graph/resources/evidence_item.ex`
- Create: `lib/office_graph/work_graph/resources/verification_result.ex`
- Modify: `.formatter.exs`

- [ ] **Step 1: Add Ash formatter imports**

Modify `.formatter.exs`:

```elixir
[
  import_deps: [:ash, :ash_postgres, :ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"]
]
```

- [ ] **Step 2: Create the WorkGraph Ash domain**

Create `lib/office_graph/work_graph/domain.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  resources do
    resource OfficeGraph.WorkGraph.Resources.Signal
    resource OfficeGraph.WorkGraph.Resources.Task
    resource OfficeGraph.WorkGraph.Resources.ReviewFinding
    resource OfficeGraph.WorkGraph.Resources.VerificationCheck
    resource OfficeGraph.WorkGraph.Resources.Artifact
    resource OfficeGraph.WorkGraph.Resources.EvidenceItem
    resource OfficeGraph.WorkGraph.Resources.VerificationResult
  end
end
```

- [ ] **Step 3: Create `Signal` Ash resource**

Create `lib/office_graph/work_graph/resources/signal.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Resources.Signal do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "signals"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :body_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :workspace_id, :graph_item_id, :body_document_id, :title, :state]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end

    policy action(:create) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end
  end

  graphql do
    type :signal
  end

  json_api do
    type "signal"
  end
end
```

- [ ] **Step 4: Create `Task` Ash resource**

Create `lib/office_graph/work_graph/resources/task.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Resources.Task do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "tasks"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :source_signal_id, :uuid, allow_nil?: true, public?: true
    attribute :body_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :graph_item_id,
        :source_signal_id,
        :body_document_id,
        :title,
        :lifecycle_state
      ]
    end

    update :mark_verified_complete do
      accept []
      change set_attribute(:lifecycle_state, "verified_complete")
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end

    policy action([:create, :mark_verified_complete]) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end
  end

  graphql do
    type :task
  end

  json_api do
    type "task"
  end
end
```

- [ ] **Step 5: Create `ReviewFinding` Ash resource**

Create `lib/office_graph/work_graph/resources/review_finding.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Resources.ReviewFinding do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "review_findings"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :task_id, :uuid, allow_nil?: false, public?: true
    attribute :body_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :workspace_id, :graph_item_id, :task_id, :body_document_id, :title, :lifecycle_state]
    end

    update :mark_verified_complete do
      accept []
      change set_attribute(:lifecycle_state, "verified_complete")
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end

    policy action([:create, :mark_verified_complete]) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end
  end

  graphql do
    type :review_finding
  end

  json_api do
    type "review_finding"
  end
end
```

- [ ] **Step 6: Create `VerificationCheck` Ash resource**

Create `lib/office_graph/work_graph/resources/verification_check.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Resources.VerificationCheck do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "verification_checks"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :review_finding_id, :uuid, allow_nil?: false, public?: true
    attribute :description_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :lifecycle_state, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :graph_item_id,
        :review_finding_id,
        :description_document_id,
        :title,
        :lifecycle_state
      ]
    end

    update :mark_satisfied do
      accept []
      change set_attribute(:lifecycle_state, "satisfied")
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end

    policy action([:create, :mark_satisfied]) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end
  end

  graphql do
    type :verification_check
  end

  json_api do
    type "verification_check"
  end
end
```

- [ ] **Step 7: Create evidence/artifact/result Ash resources**

Create `lib/office_graph/work_graph/resources/artifact.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Resources.Artifact do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "artifacts"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :uri, :string, allow_nil?: true, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :workspace_id, :graph_item_id, :title, :uri]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end

    policy action(:create) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end
  end

  graphql do
    type :artifact
  end

  json_api do
    type "artifact"
  end
end
```

Create `lib/office_graph/work_graph/resources/evidence_item.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Resources.EvidenceItem do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "evidence_items"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :graph_item_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :artifact_id, :uuid, allow_nil?: true, public?: true
    attribute :body_document_id, :uuid, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :graph_item_id,
        :verification_check_id,
        :artifact_id,
        :body_document_id,
        :title,
        :state
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end

    policy action(:create) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end
  end

  graphql do
    type :evidence_item
  end

  json_api do
    type "evidence_item"
  end
end
```

Create `lib/office_graph/work_graph/resources/verification_result.ex`:

```elixir
defmodule OfficeGraph.WorkGraph.Resources.VerificationResult do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "verification_results"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :evidence_item_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :result, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :verification_check_id,
        :evidence_item_id,
        :operation_id,
        :result
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end

    policy action(:create) do
      authorize_if OfficeGraph.Authorization.Checks.HasCapability
    end
  end

  graphql do
    type :verification_result
  end

  json_api do
    type "verification_result"
  end
end
```

- [ ] **Step 8: Run the conformance test again**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/architecture/ash_conformance_test.exs
```

Expected: fail because the policy check module does not exist yet.

- [ ] **Step 9: Commit the Ash resource skeleton**

Run:

```bash
git add .formatter.exs lib/office_graph/work_graph/domain.ex lib/office_graph/work_graph/resources
git commit -m "feat: add WorkGraph Ash resources"
```

## Task 3: Add The Shared Ash Authorization Check

**Files:**
- Create: `lib/office_graph/authorization/checks/has_capability.ex`
- Test: `test/office_graph/architecture/ash_conformance_test.exs`

- [ ] **Step 1: Add a failing focused policy test**

Append this test to `test/office_graph/architecture/ash_conformance_test.exs`:

```elixir
  test "WorkGraph Ash resources use the shared authorization check" do
    for resource <- @required_resources do
      source =
        resource
        |> inspect()
        |> String.replace_prefix("OfficeGraph.", "lib/office_graph/")
        |> Macro.underscore()
        |> Kernel.<>(".ex")

      assert File.read!(source) =~ "OfficeGraph.Authorization.Checks.HasCapability"
    end
  end
```

- [ ] **Step 2: Create the policy check module**

Create `lib/office_graph/authorization/checks/has_capability.ex`:

```elixir
defmodule OfficeGraph.Authorization.Checks.HasCapability do
  @moduledoc false

  use Ash.Policy.SimpleCheck

  @action_capabilities %{
    read: :skeleton_read,
    create: :manual_intake_submit,
    mark_verified_complete: :verification_complete,
    mark_satisfied: :verification_complete
  }

  @impl true
  def describe(_opts), do: "actor has the Office Graph capability required by the Ash action"

  @impl true
  def match?(actor, %{action: %{name: action_name}}, _opts) do
    capability = Map.get(@action_capabilities, action_name, :skeleton_read)

    case OfficeGraph.Authorization.authorize(actor, capability,
           organization_id: actor && actor.organization_id
         ) do
      :ok -> true
      {:error, :forbidden} -> false
    end
  end
end
```

- [ ] **Step 3: Run the architecture test**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/architecture/ash_conformance_test.exs
```

Expected: pass the domain/resource/policy checks.

- [ ] **Step 4: Commit the shared authorization check**

Run:

```bash
git add lib/office_graph/authorization/checks/has_capability.ex test/office_graph/architecture/ash_conformance_test.exs
git commit -m "feat: add Ash authorization check"
```

## Task 4: Route Normal WorkGraph Mutations Through Ash Actions

**Files:**
- Modify: `lib/office_graph/work_graph.ex`
- Test: `test/office_graph/work_graph/walking_skeleton_test.exs`
- Test: `test/office_graph/proposed_changes/proposed_changes_test.exs`
- Test: `test/office_graph/architecture/ash_conformance_test.exs`

- [ ] **Step 1: Add a failing test that proves returned loop records are Ash structs**

Append to `test/office_graph/work_graph/walking_skeleton_test.exs`:

```elixir
  test "walking-loop typed resources are created through Ash resource modules" do
    owner = OfficeGraph.Foundation.bootstrap_local_owner()

    {:ok, intake} =
      OfficeGraph.Integrations.submit_manual_intake(owner.session_context, %{
        source_identity: "manual:ash-proof",
        replay_identity: "ash-proof-1",
        body: "Ash backed loop resource proof."
      })

    {:ok, applied} =
      OfficeGraph.ProposedChanges.apply_all(
        owner.session_context,
        intake.operation,
        intake.proposed_changes
      )

    assert %OfficeGraph.WorkGraph.Resources.Signal{} = applied.signal
    assert %OfficeGraph.WorkGraph.Resources.Task{} = applied.task
    assert %OfficeGraph.WorkGraph.Resources.ReviewFinding{} = applied.review_finding
    assert %OfficeGraph.WorkGraph.Resources.VerificationCheck{} = applied.verification_check
  end
```

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/walking_skeleton_test.exs
```

Expected: fail because current actions return Ecto schema structs.

- [ ] **Step 2: Add private Ash action helpers in `WorkGraph`**

In `lib/office_graph/work_graph.ex`, add aliases:

```elixir
  alias OfficeGraph.WorkGraph.Resources.{
    Artifact,
    EvidenceItem,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck,
    VerificationResult
  }

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceItem,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck,
    VerificationResult
  }
```

Do not leave duplicate aliases with the same final module names. Use `as:` aliases for the old Ecto schemas:

```elixir
  alias OfficeGraph.WorkGraph.Artifact, as: ArtifactSchema
  alias OfficeGraph.WorkGraph.EvidenceItem, as: EvidenceItemSchema
  alias OfficeGraph.WorkGraph.ReviewFinding, as: ReviewFindingSchema
  alias OfficeGraph.WorkGraph.Task, as: TaskSchema
  alias OfficeGraph.WorkGraph.VerificationCheck, as: VerificationCheckSchema

  alias OfficeGraph.WorkGraph.Resources.Artifact
  alias OfficeGraph.WorkGraph.Resources.EvidenceItem
  alias OfficeGraph.WorkGraph.Resources.ReviewFinding
  alias OfficeGraph.WorkGraph.Resources.Signal
  alias OfficeGraph.WorkGraph.Resources.Task
  alias OfficeGraph.WorkGraph.Resources.VerificationCheck
  alias OfficeGraph.WorkGraph.Resources.VerificationResult
```

Add this helper:

```elixir
  defp ash_create!(resource, attrs, session_context) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, actor: session_context)
    |> Ash.create!()
  end

  defp ash_update!(record, action, session_context) do
    record
    |> Ash.Changeset.for_update(action, %{}, actor: session_context)
    |> Ash.update!()
  end
```

- [ ] **Step 3: Change create actions to call Ash inside existing graph transactions**

For `create_signal/3`, keep the graph item `Repo.insert` but replace the current `Signal.changeset(%Signal{id: signal_id}, attrs)` insert with:

```elixir
      Repo.transaction(fn ->
        graph_item =
          GraphItem.changeset(%GraphItem{id: graph_item_id}, %{
            organization_id: session_context.organization_id,
            workspace_id: session_context.workspace_id,
            resource_type: "signal",
            resource_id: signal_id,
            title: attrs[:title]
          })
          |> Repo.insert!()

        signal =
          ash_create!(
            Signal,
            %{
              id: signal_id,
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item_id,
              body_document_id: document.id,
              title: attrs[:title],
              state: "open"
            },
            session_context
          )

        %{graph_item: graph_item, signal: signal, document: document}
      end)
      |> case do
        {:ok, %{signal: signal} = result} ->
          trace!(operation, "signal.create", "signal", signal.id)
          {:ok, result}

        {:error, reason} ->
          {:error, reason}
      end
```

Apply the same explicit transaction structure for `create_task/4`, `create_review_finding/4`, and `create_verification_check/4`: graph item and relationship remain Ecto inserts; typed record insert uses `ash_create!/3`.

- [ ] **Step 4: Change completion updates to Ash update actions**

In `complete_verification/4`, keep Ecto reads for existing review/task lookup until a read-model replacement exists:

```elixir
      review_finding_schema = Repo.get!(ReviewFindingSchema, verification_check.review_finding_id)
      task_schema = Repo.get!(TaskSchema, review_finding_schema.task_id)
```

Inside the transaction, replace typed inserts with `ash_create!/3` for `Artifact`, `EvidenceItem`, and `VerificationResult`. Replace lifecycle updates with Ash updates after loading the Ash records:

```elixir
        verification_check_record = Ash.get!(VerificationCheck, verification_check.id, actor: session_context)
        review_finding_record = Ash.get!(ReviewFinding, review_finding_schema.id, actor: session_context)
        task_record = Ash.get!(Task, task_schema.id, actor: session_context)

        verification_check = ash_update!(verification_check_record, :mark_satisfied, session_context)
        review_finding = ash_update!(review_finding_record, :mark_verified_complete, session_context)
        task = ash_update!(task_record, :mark_verified_complete, session_context)
```

Return the Ash records in the existing response map.

- [ ] **Step 5: Run focused domain-loop tests**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/walking_skeleton_test.exs test/office_graph/proposed_changes/proposed_changes_test.exs
```

Expected: pass with existing behavior preserved and the new Ash-struct test green.

- [ ] **Step 6: Commit the Ash action routing**

Run:

```bash
git add lib/office_graph/work_graph.ex test/office_graph/work_graph/walking_skeleton_test.exs
git commit -m "feat: route work graph mutations through Ash"
```

## Task 5: Add The Architecture Conformance Gate

**Files:**
- Modify: `mix.exs`
- Modify: `bin/verify-backend`
- Create: `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md`
- Test: `test/office_graph/architecture/ash_conformance_test.exs`

- [ ] **Step 1: Create the exception ledger**

Create `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md`:

```markdown
# Architecture Exceptions

This file lists direct Ecto/SQL paths that remain after the Ash repair. Each
entry must cite the approved escape-hatch category from
`design-code-organization-and-boundaries` or `first-backend-walking-skeleton`.

## Direct Ecto Mutation Paths

| File | Category | Reason | Follow-up |
| --- | --- | --- | --- |
| `lib/office_graph/work_graph.ex` | Graph identity and relationships | Graph item plus relationship writes must remain in the same transaction as Ash-backed typed resource creation. | Keep; reassess after graph identity has its own Ash-aware service. |
| `lib/office_graph/integrations.ex` | Raw archive and idempotency | Replay identity and raw archive writes are an approved direct path for adapter storage. | Move stable integration records to Ash in a future integration-resource change. |
| `lib/office_graph/operations.ex` | Operation correlation | Operation correlation is the shared operation spine. | Keep as shared contract unless a future Operations Ash domain is introduced. |
| `lib/office_graph/audit.ex` | Audit append | Audit append writes are shared side effects used by Ash and non-Ash paths. | Keep append-only unless audit becomes an Ash resource later. |
| `lib/office_graph/revisions.ex` | Revision append | Revision append writes are shared side effects used by Ash and non-Ash paths. | Keep append-only unless revisions become an Ash resource later. |
| `lib/office_graph/identity.ex` | Local bootstrap | Current owner bootstrap remains narrowed to local/test setup. | Convert to Ash when identity/authentication implementation starts. |
| `lib/office_graph/tenancy.ex` | Local bootstrap | Current tenancy bootstrap remains narrowed to local/test setup. | Convert to Ash when tenancy administration implementation starts. |
| `lib/office_graph/authorization.ex` | Local bootstrap and policy bridge | Capability/role bootstrap remains narrowed; runtime policy check is shared by Ash resources. | Convert durable authorization records to Ash with enterprise governance implementation. |
| `lib/office_graph/proposed_changes.ex` | Proposed-change orchestration | Proposed graph changes are the mutation review ledger for adapter-generated writes. | Add Ash resource/actions once proposed-change workflow grows beyond skeleton scope. |
| `lib/office_graph/content.ex` | Rich text v1 narrow path | Document/block creation is intentionally skeletal. | Convert to Content Ash domain when rich text v1 is expanded. |
```

- [ ] **Step 2: Add a Mix alias for architecture conformance**

Modify `mix.exs` aliases:

```elixir
      "architecture.conformance": ["test test/office_graph/architecture/ash_conformance_test.exs"],
      verify: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "boundary.check",
        "architecture.conformance",
        "test"
      ],
```

Keep the existing `precommit` alias and add `"architecture.conformance"` before `"test"` there too.

- [ ] **Step 3: Add the gate to `bin/verify-backend`**

Modify `bin/verify-backend`:

```sh
#!/usr/bin/env sh
set -eu

mix compile --warnings-as-errors
mix format --check-formatted
mix boundary.check
mix architecture.conformance
mix test
openspec validate first-backend-walking-skeleton --strict
openspec validate --changes --strict
```

- [ ] **Step 4: Run the conformance gate**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix architecture.conformance
```

Expected: pass.

- [ ] **Step 5: Commit the conformance gate**

Run:

```bash
git add mix.exs bin/verify-backend openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md
git commit -m "chore: add architecture conformance gate"
```

## Task 6: Tighten OpenSpec Evidence And Task Tracking

**Files:**
- Modify: `openspec/changes/first-backend-walking-skeleton/tasks.md`
- Modify: `openspec/changes/first-backend-walking-skeleton/implementation-summary.md`
- Modify: `openspec/changes/first-backend-walking-skeleton/specs/walking-skeleton-verification/spec.md`
- Modify: `openspec/changes/first-backend-walking-skeleton/specs/walking-skeleton-persistence/spec.md`

- [ ] **Step 1: Add explicit Ash requirements to persistence spec**

Add this requirement to `openspec/changes/first-backend-walking-skeleton/specs/walking-skeleton-persistence/spec.md`:

```markdown
### Requirement: Ash Resource Ownership For Stable Loop Resources
Office Graph SHALL model stable walking-loop product records as Ash resources
owned by their bounded context.

#### Scenario: Stable graph-backed loop resource is implemented
- **WHEN** signal, task, review finding, verification check, artifact, evidence
  item, or verification result persistence is implemented
- **THEN** the typed product record MUST have an Ash resource backed by its
  owning Postgres table, registered in the owning Ash domain, and covered by
  authorization-aware Ash actions
```

- [ ] **Step 2: Add explicit conformance-gate requirement**

Add this requirement to `openspec/changes/first-backend-walking-skeleton/specs/walking-skeleton-verification/spec.md`:

```markdown
### Requirement: Architecture Conformance Gate
Office Graph SHALL verify that implementation architecture matches accepted
OpenSpec design decisions, not only externally visible behavior.

#### Scenario: Backend verification runs
- **WHEN** `bin/verify-backend` runs for the walking skeleton
- **THEN** it MUST fail if required Ash domains/resources are missing, if stable
  product mutations bypass Ash without an approved exception, or if the
  implementation summary lacks requirement-to-evidence mapping
```

- [ ] **Step 3: Reopen and add tasks**

Modify `openspec/changes/first-backend-walking-skeleton/tasks.md`:

```markdown
## 9. Ash Repair And Architecture Conformance

- [x] 9.1 Add failing Ash conformance tests for missing domains/resources and unapproved direct Repo mutation paths.
- [x] 9.2 Add WorkGraph Ash domain and AshPostgres resources for signal, task, review finding, verification check, artifact, evidence item, and verification result.
- [x] 9.3 Route normal typed WorkGraph creation and lifecycle transitions through Ash actions while preserving graph identity transaction invariants.
- [x] 9.4 Add a shared Ash authorization check that delegates to the Authorization boundary.
- [x] 9.5 Add an architecture exception ledger for remaining direct Ecto paths.
- [x] 9.6 Add architecture conformance to Mix aliases and `bin/verify-backend`.
- [x] 9.7 Update implementation summary with a requirement-to-evidence matrix.
```

Do not mark 9.x complete until the corresponding commits above exist.

- [ ] **Step 4: Add evidence matrix to implementation summary**

Append this section to `openspec/changes/first-backend-walking-skeleton/implementation-summary.md`:

```markdown
### Architecture Evidence Matrix

| Requirement | Evidence | Gate |
| --- | --- | --- |
| Phoenix API baseline | `lib/office_graph_web`, `config/*.exs`, `mix.exs` | `mix compile --warnings-as-errors` |
| Boundary context layout | `lib/office_graph/*.ex`, Boundary declarations | `mix boundary.check` |
| Stable WorkGraph resources are Ash-backed | `OfficeGraph.WorkGraph.Domain`, `OfficeGraph.WorkGraph.Resources.*` | `mix architecture.conformance` |
| Graph identity plus typed resource creation is atomic | `OfficeGraph.WorkGraph` explicit transactions with Ash typed inserts | `test/office_graph/work_graph/persistence_test.exs` |
| Direct Ecto paths are approved exceptions | `architecture-exceptions.md` | `test/office_graph/architecture/ash_conformance_test.exs` |
| GraphQL and JSON use shared actions | `OfficeGraph.ApiSupport`, `OfficeGraphWeb.Schema`, `WalkingSkeletonController` | `test/office_graph_web/api_smoke_test.exs` |
| OpenSpec remains valid | `openspec/changes/first-backend-walking-skeleton/**/*.md` | `openspec validate --changes --strict` |
```

- [ ] **Step 5: Validate OpenSpec**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate first-backend-walking-skeleton --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
```

Expected: both pass.

- [ ] **Step 6: Commit the OpenSpec repair**

Run:

```bash
git add openspec/changes/first-backend-walking-skeleton
git commit -m "docs: tighten Ash conformance evidence"
```

## Task 7: Full Verification And Final Review

**Files:**
- All files changed in Tasks 1-6

- [ ] **Step 1: Run formatter**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix format
```

Expected: formatter completes without errors.

- [ ] **Step 2: Run full backend gate**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify-backend
```

Expected:

```text
mix compile --warnings-as-errors
mix format --check-formatted
mix boundary.check
mix architecture.conformance
mix test
openspec validate first-backend-walking-skeleton --strict
openspec validate --changes --strict
```

All commands must pass.

- [ ] **Step 3: Search for remaining mismatch indicators**

Run:

```bash
rg -n "use Ash|Ash\\.Domain|AshPostgres\\.DataLayer|Repo\\.(insert!?|update!?|delete!?|transaction)|Ecto\\.Multi\\.(insert|update|delete)" lib test openspec/changes/first-backend-walking-skeleton
```

Expected: Ash domain/resource matches exist; direct Repo mutation matches are either in Ash-routed `WorkGraph` graph identity transaction code or listed in `architecture-exceptions.md`.

- [ ] **Step 4: Commit final verification artifacts if needed**

If formatter or verification changed files, run:

```bash
git add .
git commit -m "chore: finalize Ash conformance repair"
```

- [ ] **Step 5: Report handoff**

Final handoff must include:

```text
Implemented Ash repair for first-backend-walking-skeleton.
Verification: nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify-backend
OpenSpec: first-backend-walking-skeleton remains active until reviewed; do not archive before review.
Remaining direct Ecto paths: documented in architecture-exceptions.md.
```

## Self-Review

- Spec coverage: The plan covers the missing Ash domain/resource implementation, the Ash/Ecto boundary, authorization-aware Ash actions, API behavior preservation, OpenSpec evidence, and verification gates.
- Placeholder scan: No `TBD`, `TODO`, or unspecified implementation steps remain. Each code-changing task names files, commands, and expected outcomes.
- Type consistency: Ash resource modules live under `OfficeGraph.WorkGraph.Resources.*`; the Ash domain is `OfficeGraph.WorkGraph.Domain`; existing Ecto schemas remain under `OfficeGraph.WorkGraph.*` and must be aliased with `as:` when both are needed in the same module.
