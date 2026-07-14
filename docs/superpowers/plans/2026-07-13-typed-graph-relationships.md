# Typed Graph Relationships Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace free-form graph edges with a migration-owned typed relationship registry, lifecycle-aware commands, and authorization-filtered reads.

**Architecture:** WorkGraph owns relational relationship definitions and endpoint rules, while every persisted edge references one canonical definition and records explicit scope, lifecycle, actor, operation, and provenance. Named WorkGraph commands validate endpoint compatibility and authorization transactionally; only acyclic definitions pay for bounded, serialized cycle checks.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash 3, AshPostgres, Ecto/Postgres, AshGraphql, AshJsonApi, ExUnit, OpenSpec, Nix.

## Global Constraints

- Enter the project Nix flake for every runtime and CLI command.
- Treat `openspec/changes/implement-typed-graph-relationships/` as the behavioral source of truth.
- Install the accepted vocabulary through migrations; do not add registry administration APIs or UI.
- Keep relationship bodies and explanations in owning records, not edge metadata.
- Never grant access because an edge exists; authorize relationship scope and both endpoints.
- Preserve the unreleased-data rewrite: `produced_task` becomes reversed `generated_from`, `has_review_finding` becomes reversed `review_finding_for`, `requires_verification` becomes `requires_check`, `has_evidence` becomes `evidenced_by`, and `references_artifact` becomes `generated_from`.
- Do not add GitHub-specific or agent-specific relationship definitions in this change.

---

### Task 1: Relationship Registry Persistence

**Files:**
- Create: `priv/repo/migrations/20260713100000_create_relationship_registry.exs`
- Create: `lib/office_graph/work_graph/relationship_definition.ex`
- Create: `lib/office_graph/work_graph/relationship_endpoint_rule.ex`
- Create: `lib/office_graph/work_graph/relationship_definitions.ex`
- Modify: `lib/office_graph/work_graph/domain.ex`
- Test: `test/office_graph/work_graph/relationship_registry_test.exs`
- Modify: `test/office_graph/architecture/ash_api_ledger_conformance_test.exs`

**Interfaces:**
- Produces: `OfficeGraph.WorkGraph.RelationshipDefinitions.fetch_by_key(String.t()) :: {:ok, RelationshipDefinition.t()} | {:error, {:unknown_relationship_definition, String.t()}}`.
- Produces: private Ash resources `RelationshipDefinition` and `RelationshipEndpointRule`; neither exposes create/update/destroy through GraphQL or JSON API.
- Installs definition keys `contained_in`, `decomposes_to`, `depends_on`, `blocked_by`, `generated_from`, `requires_check`, `satisfied_by`, `evidenced_by`, `review_finding_for`, `discussed_in`, `references_external`, and `affects_scope` with explicit endpoint rules.
- Sets cycle policy `forbid` for `contained_in`, `decomposes_to`, `depends_on`, and `blocked_by`; sets `allow` for the other eight definitions.
- Installs the endpoint semantics fixed in `openspec/specs/graph-relationships/spec.md`: containment targets scope items; decomposition targets child work/check/finding items; dependency/blocking connect work items; provenance connects graph/proposal/evidence items to source items; requirements connect tasks/findings/requirements/decisions to checks; satisfaction/evidence connect work/check/finding/run outputs to evidence/results; review findings target reviewed items; discussion targets conversations; external references target external-reference items; affected-scope targets scope/resource items.

- [ ] **Step 1: Write the registry contract test**

```elixir
defmodule OfficeGraph.WorkGraph.RelationshipRegistryTest do
  use OfficeGraph.DataCase, async: true

  alias OfficeGraph.WorkGraph.RelationshipDefinitions

  test "migration installs the canonical registry without public mutations" do
    assert {:ok, definition} = RelationshipDefinitions.fetch_by_key("review_finding_for")
    assert definition.family == "review"
    assert definition.direction == "directed"
    assert definition.cycle_policy == "allow"

    assert Enum.map(definition.endpoint_rules, &{&1.source_kind, &1.target_kind}) == [
             {"review_finding", "task"}
           ]

    refute function_exported?(OfficeGraph.WorkGraph.Domain, :create_relationship_definition, 1)
  end

  test "unknown keys fail with a stable error" do
    assert {:error, {:unknown_relationship_definition, "invented"}} =
             RelationshipDefinitions.fetch_by_key("invented")
  end
end
```

- [ ] **Step 2: Run the focused test and observe the missing registry**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_registry_test.exs`

Expected: FAIL because `RelationshipDefinitions` and the registry tables do not exist.

- [ ] **Step 3: Add the migration-owned registry and read boundary**

Create relational tables with typed columns and install the accepted rows in `up/0`. Keep the resource actions private and preload endpoint rules in the lookup.

```elixir
defmodule OfficeGraph.WorkGraph.RelationshipDefinitions do
  @moduledoc false

  alias OfficeGraph.WorkGraph.RelationshipDefinition
  require Ash.Query

  @spec fetch_by_key(String.t()) ::
          {:ok, RelationshipDefinition.t()}
          | {:error, {:unknown_relationship_definition, String.t()}}
          | {:error, term()}
  def fetch_by_key(key) when is_binary(key) do
    RelationshipDefinition
    |> Ash.Query.filter(key == ^key and lifecycle == "active")
    |> Ash.Query.load(:endpoint_rules)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:unknown_relationship_definition, key}}
      result -> result
    end
  end
end
```

The migration must enforce unique definition keys, unique endpoint-rule triples, allowed direction/lifecycle/cycle values, and indexes on active keys and endpoint kinds. Add both resources to `WorkGraph.Domain` and the backend ownership inventory.

- [ ] **Step 4: Run registry and architecture tests**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_registry_test.exs test/office_graph/architecture/ash_api_ledger_conformance_test.exs`

Expected: PASS with the migration-installed vocabulary and no public registry mutations.

- [ ] **Step 5: Commit the registry checkpoint**

```bash
git add priv/repo/migrations/20260713100000_create_relationship_registry.exs lib/office_graph/work_graph test/office_graph/work_graph/relationship_registry_test.exs test/office_graph/architecture/ash_api_ledger_conformance_test.exs
git commit -m "feat: add typed relationship registry"
```

### Task 2: Definition-Backed Edge Migration

**Files:**
- Create: `priv/repo/migrations/20260713101000_type_graph_relationships.exs`
- Modify: `lib/office_graph/work_graph/graph_relationship.ex`
- Create: `test/office_graph/work_graph/relationship_migration_test.exs`
- Modify: `test/office_graph/work_graph/persistence_test.exs`

**Interfaces:**
- Consumes: `relationship_definitions.id` and the canonical keys installed by Task 1.
- Produces: `graph_relationships.definition_id`, `organization_id`, nullable `workspace_id`, `lifecycle`, `asserting_principal_id`, `operation_id`, `valid_from`, nullable `valid_until`, `run_id`, `integration_event_id`, `supersedes_relationship_id`, and `tombstone_id`.
- Removes: writable `relationship_type` input and the legacy database column after verified backfill.

- [ ] **Step 1: Write migration and resource failures first**

```elixir
test "all legacy edge values become canonical typed edges" do
  legacy = insert_legacy_relationships!()
  migrate_to!(20260713101000)

  task = relationship_by_id!(legacy.produced_task_relationship_id)
  assert task.definition_key == "generated_from"
  assert task.source_item_id == legacy.task_item_id
  assert task.target_item_id == legacy.signal_item_id

  review = relationship_by_id!(legacy.review_relationship_id)
  assert review.definition_key == "review_finding_for"
  assert review.source_item_id == legacy.review_finding_item_id
  assert review.target_item_id == legacy.task_item_id

  check = relationship_by_id!(legacy.check_relationship_id)
  assert check.definition_key == "requires_check"
  assert check.source_item_id == legacy.review_finding_item_id
  assert check.target_item_id == legacy.verification_check_item_id

  evidence = relationship_by_id!(legacy.evidence_relationship_id)
  assert evidence.definition_key == "evidenced_by"
  assert evidence.source_item_id == legacy.verification_check_item_id
  assert evidence.target_item_id == legacy.evidence_item_id

  artifact = relationship_by_id!(legacy.artifact_relationship_id)
  assert artifact.definition_key == "generated_from"
  assert artifact.source_item_id == legacy.evidence_item_id
  assert artifact.target_item_id == legacy.artifact_item_id
end

test "unknown legacy values abort before changing rows" do
  insert_legacy_relationship!(relationship_type: "unknown_edge")

  assert_raise Postgrex.Error, ~r/unknown graph relationship types.*unknown_edge/, fn ->
    migrate_to!(20260713101000)
  end
end
```

- [ ] **Step 2: Run the migration tests and observe missing typed columns**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_migration_test.exs test/office_graph/work_graph/persistence_test.exs`

Expected: FAIL because the typed edge migration and resource attributes are absent.

- [ ] **Step 3: Implement the guarded backfill and resource shape**

Use SQL inside the migration to reject unknown values, verify the legacy endpoint kinds before reversal, populate definition/scope/lifecycle/provenance columns, then enforce constraints and remove `relationship_type`. Model the canonical relation on the Ash resource:

```elixir
belongs_to :definition, OfficeGraph.WorkGraph.RelationshipDefinition do
  source_attribute :definition_id
  allow_nil? false
end

belongs_to :organization, OfficeGraph.Tenancy.Organization do
  source_attribute :organization_id
  allow_nil? false
end

belongs_to :governing_workspace, OfficeGraph.Tenancy.Workspace do
  source_attribute :workspace_id
end

belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
  source_attribute :operation_id
  allow_nil? false
end

identity :active_definition_edge,
         [:organization_id, :definition_id, :source_item_id, :target_item_id],
         where: expr(lifecycle == "active")
```

The rollback must derive only the five supported legacy values from endpoint
rules, restore their old names and directions, and raise if post-change rows
cannot be represented without loss.

- [ ] **Step 4: Reset and verify both migration directions**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix ecto.reset`

Expected: PASS with all migrations applied.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_migration_test.exs test/office_graph/work_graph/persistence_test.exs`

Expected: PASS, including unknown-value and endpoint-direction guards.

- [ ] **Step 5: Commit the edge migration checkpoint**

```bash
git add priv/repo/migrations/20260713101000_type_graph_relationships.exs lib/office_graph/work_graph/graph_relationship.ex test/office_graph/work_graph/relationship_migration_test.exs test/office_graph/work_graph/persistence_test.exs
git commit -m "feat: migrate graph edges to typed definitions"
```

### Task 3: Named Relationship Commands And Cycle Safety

**Files:**
- Create: `lib/office_graph/work_graph/relationship_request.ex`
- Create: `lib/office_graph/work_graph/relationship_commands.ex`
- Create: `lib/office_graph/work_graph/relationship_cycle_policy.ex`
- Create: `lib/office_graph/work_graph/relationship_operation_policy.ex`
- Modify: `lib/office_graph/work_graph.ex`
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph/authorization.ex`
- Modify: `lib/office_graph/foundation/bootstrap.ex`
- Modify: `lib/office_graph/work_graph/proposal_commands.ex`
- Modify: `lib/office_graph/work_graph/command_support.ex`
- Modify: `lib/office_graph/work_graph/verification_commands.ex`
- Modify: `lib/office_graph/verification.ex`
- Test: `test/office_graph/work_graph/relationship_commands_test.exs`
- Test: `test/office_graph/work_graph/relationship_cycle_concurrency_test.exs`

**Interfaces:**
- Produces: `WorkGraph.create_relationship(session, operation, %RelationshipRequest{})`.
- Produces: `WorkGraph.supersede_relationship(session, operation, relationship, %RelationshipRequest{})`.
- Produces: `WorkGraph.archive_relationship(session, operation, relationship, attrs)` and `WorkGraph.restore_relationship(session, operation, relationship, attrs)`.
- `RelationshipRequest.new/1` requires `definition_key`, `source_item_id`, `target_item_id`; accepts `workspace_id`, `valid_from`, `run_id`, and `integration_event_id`.
- Produces human lifecycle action keys `graph_relationship.create`, `graph_relationship.supersede`, `graph_relationship.archive`, `graph_relationship.restore`, and `graph_relationship.cross_workspace`; proposal/evidence operations remain valid only for the canonical relationships they own.

- [ ] **Step 1: Write behavior and replay tests**

```elixir
test "create validates endpoints and replays one active edge", context do
  request = %RelationshipRequest{
    definition_key: "review_finding_for",
    source_item_id: context.review_finding_item.id,
    target_item_id: context.task_item.id,
    workspace_id: context.session.workspace_id
  }

  assert {:ok, first} = WorkGraph.create_relationship(context.session, context.operation, request)
  assert {:ok, replay} = WorkGraph.create_relationship(context.session, context.operation, request)
  assert replay.id == first.id

  reversed = %{request | source_item_id: request.target_item_id, target_item_id: request.source_item_id}
  assert {:error, {:invalid_relationship_endpoints, "review_finding_for"}} =
           WorkGraph.create_relationship(context.session, context.operation, reversed)
end

test "an edge never reveals an unauthorized endpoint", context do
  assert {:error, :forbidden} =
           WorkGraph.create_relationship(
             context.session,
             context.operation,
             context.cross_workspace_request
           )
end
```

- [ ] **Step 2: Run focused command tests and observe missing command modules**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_commands_test.exs`

Expected: FAIL because the named commands and request type do not exist.

- [ ] **Step 3: Implement one transaction boundary for lifecycle commands**

```elixir
def create(session, operation, %RelationshipRequest{} = request) do
  with :ok <- Operations.validate_operation_context(session, operation),
       {:ok, definition} <- RelationshipDefinitions.fetch_by_key(request.definition_key),
       :ok <- RelationshipOperationPolicy.validate(operation, definition, :create),
       {:ok, endpoints} <- validate_endpoints(session, definition, request),
       :ok <- authorize_create(session, operation, definition, endpoints) do
    Repo.transaction(fn ->
      RelationshipCyclePolicy.lock_and_validate!(
        definition,
        session.organization_id,
        request
      )
      upsert_active_relationship!(session, operation, definition, request)
    end)
    |> unwrap_transaction()
  end
end
```

Implement the action allowlist without integration- or agent-specific names:

```elixir
defmodule OfficeGraph.WorkGraph.RelationshipOperationPolicy do
  @direct_actions %{
    create: "graph_relationship.create",
    supersede: "graph_relationship.supersede",
    archive: "graph_relationship.archive",
    restore: "graph_relationship.restore"
  }

  @embedded_create_actions %{
    "proposed_change.apply" =>
      MapSet.new(["generated_from", "review_finding_for", "requires_check"]),
    "evidence.accept" => MapSet.new(["evidenced_by", "generated_from"]),
    "integration.reconcile" => :registered_definition
  }

  def validate(operation, definition, :create) do
    case Map.get(@embedded_create_actions, operation.action) do
      :registered_definition -> :ok
      %MapSet{} = keys -> if MapSet.member?(keys, definition.key), do: :ok, else: forbidden()
      nil -> validate_direct(operation, :create)
    end
  end

  def validate(operation, _definition, lifecycle_action) do
    validate_direct(operation, lifecycle_action)
  end

  defp validate_direct(operation, action) do
    if Map.fetch!(@direct_actions, action) == operation.action, do: :ok, else: forbidden()
  end

  defp forbidden, do: {:error, :forbidden}
end
```

Supersede must lock the existing active row, insert the replacement with
`supersedes_relationship_id`, and archive the old row in the same transaction.
Restore must reject definitions, endpoints, or authority that are no longer
eligible. Update proposal application to call canonical requests for
`generated_from`, `review_finding_for`, and `requires_check`; update both
verification paths to call `evidenced_by` and `generated_from` commands instead
of inserting evidence edges directly. Every branch still calls Authorization
for the actor, governing scope, definition posture, and cross-workspace
capability after this action allowlist passes.

- [ ] **Step 4: Add the concurrent cycle test before the cycle guard**

```elixir
test "concurrent depends_on writes cannot commit a cycle", context do
  first = depends_on_request(context.a.id, context.b.id)
  second = depends_on_request(context.b.id, context.a.id)

  results =
    [first, second]
    |> Task.async_stream(
      &WorkGraph.create_relationship(context.session, context.operation, &1),
      ordered: false,
      max_concurrency: 2
    )
    |> Enum.map(fn {:ok, result} -> result end)

  assert Enum.count(results, &match?({:ok, _}, &1)) == 1
  assert Enum.count(results, &match?({:error, {:relationship_cycle, "depends_on"}}, &1)) == 1
end
```

- [ ] **Step 5: Implement definition-scoped serialization and bounded traversal**

Acquire a PostgreSQL transaction advisory lock derived from organization and definition IDs before recursive traversal. Traverse only active edges for the definition, stop at the source, and cap visited rows using an explicit `@max_cycle_nodes` value; return `{:relationship_cycle_check_limit, definition.key}` when the cap is exceeded.

```elixir
@max_cycle_nodes 10_000

def lock_and_validate!(%{cycle_policy: "forbid"} = definition, organization_id, request) do
  Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
    organization_id <> ":" <> definition.id
  ])

  case reachable?(definition.id, request.target_item_id, request.source_item_id, @max_cycle_nodes) do
    false -> :ok
    true -> Repo.rollback({:relationship_cycle, definition.key})
    :limit -> Repo.rollback({:relationship_cycle_check_limit, definition.key})
  end
end

def lock_and_validate!(%{cycle_policy: "allow"}, _organization_id, _request), do: :ok
```

- [ ] **Step 6: Run command, proposal, and concurrency tests**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_commands_test.exs test/office_graph/work_graph/relationship_cycle_concurrency_test.exs test/office_graph/proposed_changes/proposed_changes_test.exs`

Expected: PASS with exactly one concurrent cyclic insert rejected.

- [ ] **Step 7: Commit the command checkpoint**

```bash
git add lib/office_graph/work_graph.ex lib/office_graph/work_graph/relationship_request.ex lib/office_graph/work_graph/relationship_commands.ex lib/office_graph/work_graph/relationship_cycle_policy.ex lib/office_graph/work_graph/relationship_operation_policy.ex lib/office_graph/work_graph/proposal_commands.ex lib/office_graph/work_graph/command_support.ex lib/office_graph/work_graph/verification_commands.ex lib/office_graph/operations.ex lib/office_graph/authorization.ex lib/office_graph/foundation/bootstrap.ex lib/office_graph/verification.ex test/office_graph/work_graph/relationship_commands_test.exs test/office_graph/work_graph/relationship_cycle_concurrency_test.exs test/office_graph/proposed_changes/proposed_changes_test.exs test/office_graph/verification test/office_graph/foundation/bootstrap_test.exs
git commit -m "feat: add typed relationship commands"
```

### Task 4: Authorized Reads, Projections, And APIs

**Files:**
- Modify: `lib/office_graph/work_graph/queries.ex`
- Modify: `lib/office_graph/projections/operator_workflow.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/queries.ex`
- Modify: `lib/office_graph_web/graphql/operator_workflow/types.ex`
- Modify: `lib/office_graph_web/json_api/router.ex`
- Modify: `test/office_graph/projections/operator_inbox_projection_test.exs`
- Create: `test/office_graph/work_graph/relationship_queries_test.exs`
- Create: `test/office_graph_web/relationship_graphql_test.exs`
- Create: `test/office_graph_web/relationship_json_test.exs`
- Modify: `assets/schema.graphql`
- Modify: `assets/app/relay/__generated__/OperatorRelationshipDetailsQuery.graphql.ts`

**Interfaces:**
- Produces: `WorkGraph.list_relationships(session, item_id, opts) :: {:ok, [relationship_view]} | {:error, :forbidden}`.
- `opts` accepts `direction: :incoming | :outgoing | :both`, `definition_keys: [String.t()]`, `lifecycle: "active" | "archived"`, and `limit: 1..100`.
- API output exposes canonical key, family, direction, lifecycle, governing scope, validity, safe provenance IDs, and authorized/redacted endpoint views; it exposes no registry mutation.

- [ ] **Step 1: Write read authorization and query-count tests**

```elixir
test "adjacency redacts an endpoint the actor cannot read", context do
  assert {:ok, [view]} =
           WorkGraph.list_relationships(context.session, context.visible_item.id,
             direction: :both,
             limit: 25
           )

  assert view.definition_key == "references"
  assert view.source.visibility == :visible
  assert view.target == %{visibility: :redacted}
end

test "bounded adjacency does not add one query per edge", context do
  insert_relationship_fanout!(context, 40)
  assert_query_count_at_most 6, fn ->
    assert {:ok, views} = WorkGraph.list_relationships(context.session, context.item.id, limit: 40)
    assert length(views) == 40
  end
end
```

- [ ] **Step 2: Run relationship read tests and observe the absent projection**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_queries_test.exs test/office_graph_web/relationship_graphql_test.exs test/office_graph_web/relationship_json_test.exs`

Expected: FAIL because canonical relationship reads and transport fields are absent.

- [ ] **Step 3: Implement bounded, batched, authorization-filtered reads**

```elixir
def list_relationships(session, item_id, opts \\ []) do
  limit = opts |> Keyword.get(:limit, 25) |> min(100) |> max(1)

  with {:ok, item} <- authorized_item(session, item_id),
       {:ok, relationships} <- read_adjacency(item, opts, limit),
       {:ok, endpoints} <- batch_authorized_endpoints(session, relationships) do
    {:ok, Enum.map(relationships, &relationship_view(&1, endpoints))}
  end
end
```

Use Relay-stable IDs in GraphQL, the same safe projection in JSON, and regenerate schema/Relay artifacts through the pinned commands. Keep definition resources out of generated mutation roots.

- [ ] **Step 4: Regenerate and verify transport artifacts**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'cd assets && pnpm relay && pnpm vitest run app/routes/operator/route.reads.test.tsx'`

Expected: `assets/schema.graphql` and Relay artifacts regenerate, and the focused route test passes.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/relationship_queries_test.exs test/office_graph_web/relationship_graphql_test.exs test/office_graph_web/relationship_json_test.exs test/office_graph/projections/operator_inbox_projection_test.exs`

Expected: PASS with endpoint redaction and bounded query counts.

- [ ] **Step 5: Commit the read/API checkpoint**

```bash
git add lib/office_graph/work_graph/queries.ex lib/office_graph/projections/operator_workflow.ex lib/office_graph_web/graphql/operator_workflow lib/office_graph_web/json_api/router.ex test/office_graph/work_graph/relationship_queries_test.exs test/office_graph_web/relationship_graphql_test.exs test/office_graph_web/relationship_json_test.exs test/office_graph/projections/operator_inbox_projection_test.exs assets/schema.graphql assets/app/relay/__generated__/OperatorRelationshipDetailsQuery.graphql.ts
git commit -m "feat: expose authorized typed relationships"
```

### Task 5: Verify, Synchronize, And Archive

**Files:**
- Modify: `openspec/changes/implement-typed-graph-relationships/tasks.md`
- Modify: `openspec/specs/typed-relationship-registry/spec.md`
- Modify: `openspec/specs/graph-relationships/spec.md`
- Modify: `openspec/specs/graph-storage-contract/spec.md`
- Move: `openspec/changes/implement-typed-graph-relationships/` to `openspec/changes/archive/2026-07-13-implement-typed-graph-relationships/`
- Move: `docs/superpowers/plans/2026-07-13-typed-graph-relationships.md` to `docs/superpowers/plans/archive/2026-07-13-typed-graph-relationships.md`
- Modify: `docs/superpowers/plans/README.md`

**Interfaces:**
- Produces: archived canonical typed-relationship specs that `add-github-review-integration` and `implement-internal-agent-runtime` can target without compatibility aliases.

- [ ] **Step 1: Run the focused backend suite**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph test/office_graph/proposed_changes test/office_graph/projections/operator_inbox_projection_test.exs test/office_graph_web/relationship_graphql_test.exs test/office_graph_web/relationship_json_test.exs test/office_graph/architecture`

Expected: PASS with zero failures.

- [ ] **Step 2: Run strict change and repository verification**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate implement-typed-graph-relationships --strict`

Expected: `Change 'implement-typed-graph-relationships' is valid`.

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command mix verify`

Expected: all backend, frontend, architecture, advisory, and OpenSpec gates pass.

Run: `git diff --check`

Expected: no output.

- [ ] **Step 3: Verify every requirement against implementation evidence**

Update each checkbox in `openspec/changes/implement-typed-graph-relationships/tasks.md` only after its named tests and implementation exist. Run `openspec show implement-typed-graph-relationships` and map every requirement scenario to at least one focused test before archiving.

- [ ] **Step 4: Synchronize and archive the completed change**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec archive implement-typed-graph-relationships --yes`

Expected: delta specs merge into canonical specs and the change moves under `openspec/changes/archive/2026-07-13-implement-typed-graph-relationships/`.

- [ ] **Step 5: Re-run strict validation after archive and commit**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --all --strict`

Expected: every canonical spec and active change validates.

```bash
git add openspec docs/superpowers/plans
git commit -m "chore: archive typed graph relationships"
```
