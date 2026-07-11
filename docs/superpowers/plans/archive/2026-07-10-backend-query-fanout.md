# Backend Query Fanout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Eliminate per-item backend query growth in packet/run collection writes and add scaling gates for cardinality-sensitive reads.

**Architecture:** Keep all writes on existing Ash `:create` actions, but invoke collection writes through `Ash.bulk_create/4`. Implement `batch_change/3` on the two query-producing validation changes so each Ash batch loads referenced resources once, then validates changesets from in-memory indexes. Use Ecto telemetry tests to assert per-source query scaling while preserving domain transactions and return contracts.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash 3.29.3, AshPostgres 2.10.0, Ecto SQL 3.14, PostgreSQL 17, ExUnit, OpenSpec 1.4.1, Nix flakes.

> **Archive status:** Completed. Checked RED steps record the intended failing scaling or missing-helper regression before implementation. All focused, repository, OpenSpec, and diff-hygiene verification completed without exceptions.

## Global Constraints

- Run every project tool through `nix --extra-experimental-features 'nix-command flakes' develop --command`.
- Use OpenSpec as the workflow source of truth; implement `eliminate-backend-query-fanout` and update its task checkboxes as work completes.
- Keep durable writes Ash-managed; do not add `Repo.insert_all`, raw SQL, a new architecture exception, or caching. Permit only the additive collection-position migration needed to preserve caller-visible ordering after bulk writes.
- Preserve existing authorization, action defaults, validation messages, transaction rollback, caller-visible ordering, and return shapes.
- Follow red-green-refactor: every production edit must be preceded by a focused failing test that fails for the expected query-shape or missing-helper reason.

---

### Task 1: Establish Read And Write Query-Scaling Regressions

**Files:**
- Modify: `test/office_graph/work_packets/work_packet_run_verification_test.exs`
- Modify: `test/office_graph/projections/operator_workflow_test.exs`
- Modify: `test/office_graph_web/generated_api_read_test.exs`

**Interfaces:**
- Consumes: `OfficeGraph.QueryCounter.count/1` and `source_count/2`.
- Produces: failing scaling tests that define the packet, run, run-state, and generated GraphQL query budgets.

- [x] **Step 1: Add packet and run collection scaling tests**

Add `alias OfficeGraph.QueryCounter` and create four required checks with the existing helper. Count packet creation and run start independently:

```elixir
test "packet and run collection writes keep query count bounded" do
  {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

  verification_checks =
    Enum.map(1..4, fn _index ->
      {:ok, verification_check} = create_required_verification_check(bootstrap.session)
      verification_check
    end)

  {:ok, packet_operation} = Operations.start_operation(bootstrap.session, :work_packet_create)

  {{:ok, packet_result}, packet_queries} =
    QueryCounter.count(fn ->
      WorkPackets.create_packet(bootstrap.session, packet_operation, %{
        title: "Bulk query packet",
        objective: "Bound packet collection writes.",
        context_summary: "Multiple packet references.",
        requirements: "Create all references atomically.",
        success_criteria: "One Ash batch per link resource.",
        autonomy_posture: "human_supervised",
        source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
        verification_check_ids: Enum.map(verification_checks, & &1.id)
      })
    end)

  assert QueryCounter.source_count(packet_queries, "work_packet_version_sources") <= 1
  assert QueryCounter.source_count(packet_queries, "work_packet_version_required_checks") <= 1

  {:ok, run_operation} = Operations.start_operation(bootstrap.session, :work_run_start)

  {{:ok, run_result}, run_queries} =
    QueryCounter.count(fn ->
      Runs.start_run(bootstrap.session, run_operation, packet_result.version, %{
        source_surface: "test",
        reason: "Exercise bulk required checks.",
        authority_posture: "human_supervised"
      })
    end)

  assert length(run_result.required_checks) == 4
  assert QueryCounter.source_count(run_queries, "run_required_checks") <= 1
end
```

- [x] **Step 2: Run the focused write test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_packets/work_packet_run_verification_test.exs
```

Expected: FAIL because packet and run link tables currently receive one insert per input.

- [x] **Step 3: Add operator run-state scaling coverage**

In `operator_workflow_test.exs`, create a run backed by four checks, count `Projections.operator_run_state/2`, and assert each child source is read at most once:

```elixir
assert QueryCounter.source_count(queries, "run_required_checks") <= 1
assert QueryCounter.source_count(queries, "execution_observations") <= 1
assert QueryCounter.source_count(queries, "evidence_candidates") <= 1
assert QueryCounter.source_count(queries, "evidence_items") <= 1
assert QueryCounter.source_count(queries, "verification_results") <= 1
```

- [x] **Step 4: Add generated GraphQL list scaling coverage**

In `generated_api_read_test.exs`, alias `OfficeGraph.QueryCounter`, seed three local scopes with `seed_scope([])`, execute the existing generated list query inside `QueryCounter.count/1`, and assert each generated resource list is read at most once:

```graphql
query GeneratedResourceReads {
  listSignals(first: 10) {
    edges { node { id title state } }
  }
  listWorkPackets(first: 10) {
    edges { node { id title state } }
  }
  listWorkRuns(first: 10) {
    edges { node { id state workPacketId } }
  }
}
```

Assert the response has no errors and these sources have counts no greater than one: `signals`, `work_packets`, and `runs`.

- [x] **Step 5: Run focused read tests**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/projections/operator_workflow_test.exs test/office_graph_web/generated_api_read_test.exs
```

Expected: PASS if AshGraphql batching and the current projections remain bounded; any failure identifies an additional read N+1 to fix before Task 4.

- [x] **Step 6: Commit the regression baseline**

```bash
git add test/office_graph/work_packets/work_packet_run_verification_test.exs test/office_graph/projections/operator_workflow_test.exs test/office_graph_web/generated_api_read_test.exs openspec/changes/eliminate-backend-query-fanout/tasks.md
git commit -m "test: cover backend query scaling"
```

### Task 2: Make Ash Reference Validation Batch-Aware

**Files:**
- Modify: `lib/office_graph/work_graph/changes/validate_same_scope_references.ex`
- Modify: `test/office_graph/work_graph/ash_authorization_test.exs`

**Interfaces:**
- Consumes: a list of `%Ash.Changeset{}` values plus the existing `references:` option.
- Produces: `batch_change/3 :: [Ash.Changeset.t()]`, with one read per referenced resource and unchanged errors.

- [x] **Step 1: Add a failing batch validation test**

Build multiple source-reference changesets, invoke `Ash.bulk_create/4` with `return_records?: true`, and count queries. Include a missing or cross-scope ID in a separate case and assert the existing message remains:

```elixir
assert Exception.message(error) =~
         "graph_item_id must reference an existing record in the target scope"
```

- [x] **Step 2: Run the validator test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/ash_authorization_test.exs
```

Expected: FAIL because `change/3` performs one `Ash.read_one/2` per changeset reference.

- [x] **Step 3: Implement `batch_change/3`**

Refactor the module around shared functions with this shape:

```elixir
@impl true
def batch_change(changesets, opts, _context) do
  references = Keyword.fetch!(opts, :references)

  loaded_references =
    references
    |> Enum.map(fn {_field, reference} -> reference_spec(reference) |> elem(0) end)
    |> Enum.uniq()
    |> Map.new(fn resource -> {resource, load_batch_resource(resource, changesets, references)} end)

  Enum.map(changesets, &validate_changeset(&1, references, loaded_references))
end
```

`load_batch_resource/3` must collect all non-nil IDs for fields targeting that resource, issue `Ash.Query.filter(id in ^ids) |> Ash.read(authorize?: false)` once, and return either an ID map or the lookup error. `validate_changeset/3` must reuse `target_scope/1`, `validate_resource_identity/4`, and the existing error builders. Keep `change/3` as the single-record path through the same validation function.

- [x] **Step 4: Run focused tests and verify GREEN**

Run the validator and packet tests. Expected: batch reference lookups are bounded; write insert assertions remain RED until Task 4.

- [x] **Step 5: Commit batch-aware reference validation**

```bash
git add lib/office_graph/work_graph/changes/validate_same_scope_references.ex test/office_graph/work_graph/ash_authorization_test.exs openspec/changes/eliminate-backend-query-fanout/tasks.md
git commit -m "perf: batch Ash reference validation"
```

### Task 3: Make Run Required-Check Validation Batch-Aware

**Files:**
- Modify: `lib/office_graph/runs/changes/validate_run_required_check_contract.ex`
- Modify: `test/office_graph/work_packets/work_packet_run_verification_test.exs`

**Interfaces:**
- Consumes: run-required-check create changesets.
- Produces: `batch_change/3` that loads runs and packet-required-check contracts once per batch.

- [x] **Step 1: Add failing direct bulk-validation tests**

Delete existing run-required-check rows for a multi-check run, then bulk-create valid inputs and assert `runs` and `work_packet_version_required_checks` query counts remain bounded. Add a second case containing a check outside the packet contract and assert the existing `verification_check_id must belong to the run packet version` error.

- [x] **Step 2: Run the focused test and verify RED**

Expected: query counts grow with changesets because the current change fetches one run and performs one `Ash.exists?/2` per check.

- [x] **Step 3: Implement `batch_change/3`**

Use this data flow:

```elixir
run_ids = changesets |> Enum.map(&attribute(&1, :run_id)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
runs_by_id = read_runs(run_ids)
packet_contracts = read_packet_required_checks(Map.values(runs_by_id))
Enum.map(changesets, &validate_from_indexes(&1, runs_by_id, packet_contracts))
```

Index packet contracts by `{work_packet_version_id, verification_check_id, organization_id, workspace_id}`. Preserve the current missing-run, non-packet-backed, and packet-mismatch error text. Keep `change/3` for single creates and share the validation predicate.

- [x] **Step 4: Run focused tests and verify GREEN**

Run the work-packet/run suite. Expected: validation reads are bounded; insert assertions remain RED until Task 4.

- [x] **Step 5: Commit run validation batching**

```bash
git add lib/office_graph/runs/changes/validate_run_required_check_contract.ex test/office_graph/work_packets/work_packet_run_verification_test.exs openspec/changes/eliminate-backend-query-fanout/tasks.md
git commit -m "perf: batch run check validation"
```

### Task 4: Replace Per-Item Creates With Ash Bulk Creates

**Files:**
- Modify: `lib/office_graph/repo.ex`
- Modify: `lib/office_graph/work_packets.ex`
- Modify: `lib/office_graph/runs.ex`
- Modify: `test/office_graph/work_packets/work_packet_run_verification_test.exs`

**Interfaces:**
- Produces: `OfficeGraph.Repo.ash_bulk_create!(resource, inputs) :: [struct()]`.
- Consumes: input maps with pre-generated `:id` values and the resource's existing private `:create` action.

- [x] **Step 1: Add focused repo-helper tests**

Cover empty input, stable ordering, and an invalid middle record. The invalid case must assert the enclosing transaction contains zero records from the attempted collection after rollback.

- [x] **Step 2: Run the helper test and verify RED**

Expected: FAIL because `Repo.ash_bulk_create!/2` does not exist.

- [x] **Step 3: Implement `ash_bulk_create!/2`**

```elixir
def ash_bulk_create!(_resource, []), do: []

def ash_bulk_create!(resource, inputs) do
  input_ids = Enum.map(inputs, &Map.fetch!(&1, :id))

  case Ash.bulk_create(inputs, resource, :create,
         authorize?: false,
         return_records?: true,
         return_errors?: true,
         stop_on_error?: true,
         transaction: false
       ) do
    %Ash.BulkResult{errors: [], records: records} ->
      records_by_id = Map.new(records, &{&1.id, &1})
      Enum.map(input_ids, &Map.fetch!(records_by_id, &1))

    %Ash.BulkResult{errors: [error | _]} ->
      rollback(error)
  end
end
```

If Ash 3.29.3 reports a non-empty error status without populating `errors`, normalize that documented result shape in the same helper and add a test for it; do not let partial success escape.

- [x] **Step 4: Migrate packet collection writes**

Replace both `Enum.map(... Repo.ash_create!)` blocks with input-map construction followed by:

```elixir
source_references = Repo.ash_bulk_create!(WorkPacketSourceReference, source_inputs)
required_checks = Repo.ash_bulk_create!(WorkPacketRequiredCheck, check_inputs)
```

- [x] **Step 5: Run packet tests and verify GREEN**

Expected: packet link inserts and validation reads remain within the scaling budgets, return order matches input order, and invalid collection members roll back the packet transaction.

- [x] **Step 6: Migrate run collection writes**

Build `RunRequiredCheck` input maps from the packet required checks and call `Repo.ash_bulk_create!/2` once. Preserve the current `%{run: run, required_checks: records}` result.

- [x] **Step 7: Run run tests and verify GREEN**

Expected: one bulk insert batch for `run_required_checks`, bounded validation reads, stable ordering, and full rollback on invalid input.

- [x] **Step 8: Commit Ash-native bulk writes**

```bash
git add lib/office_graph/repo.ex lib/office_graph/work_packets.ex lib/office_graph/runs.ex test/office_graph/work_packets/work_packet_run_verification_test.exs openspec/changes/eliminate-backend-query-fanout/tasks.md
git commit -m "perf: bulk packet and run collection writes"
```

### Task 5: Complete Read Verification And Full Verification

**Files:**
- Modify: `openspec/changes/eliminate-backend-query-fanout/tasks.md`

**Interfaces:**
- Consumes: Task 1 read-scaling tests.
- Produces: all OpenSpec tasks checked and a fully verified backend.

- [x] **Step 1: Run all focused tests**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/query_counter_test.exs test/office_graph/work_graph/ash_authorization_test.exs test/office_graph/work_packets/work_packet_run_verification_test.exs test/office_graph/projections/operator_workflow_test.exs test/office_graph_web/generated_api_read_test.exs
```

Expected: zero failures.

- [x] **Step 2: Run formatting and compilation gates**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix format --check-formatted
nix --extra-experimental-features 'nix-command flakes' develop --command mix compile --warnings-as-errors
```

Expected: both exit zero with no warnings.

- [x] **Step 3: Run full project verification**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix verify
```

Expected: all project verification checks pass.

- [x] **Step 4: Validate OpenSpec and the patch**

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
git diff --check
```

Expected: all changes pass strict validation and the diff has no whitespace errors.

- [x] **Step 5: Mark OpenSpec tasks complete and commit**

```bash
git add openspec/changes/eliminate-backend-query-fanout/tasks.md docs/superpowers/plans/2026-07-10-backend-query-fanout.md
git commit -m "docs: complete backend query fanout change"
```
