# Repo-Wide Ash Model Conformance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert every implemented durable Office Graph model to a canonical Ash resource in its owning Ash domain, remove duplicate/manual Ecto schema definitions, and harden conformance gates so this mismatch cannot recur.

**Architecture:** Existing table migrations remain the storage source for this repair; Ash resources use `AshPostgres.DataLayer` with `migrate? false` unless a later domain change intentionally moves migration ownership to Ash. The canonical model module is the Ash resource module, for example `OfficeGraph.WorkGraph.Signal`, not a parallel `OfficeGraph.WorkGraph.Resources.Signal`. Direct Ecto is reduced to explicitly ledgered transaction/read escape hatches and must not define table-backed model schemas under `lib/office_graph`.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix API, Ecto/Postgres, Ash, AshPostgres, AshGraphql, AshJsonApi, Boundary, Absinthe, OpenSpec, Docker Compose Postgres, Nix shell.

---

## Root Cause

The previous Ash repair satisfied the narrow executable gate but not the broader architecture rule. `test/office_graph/architecture/ash_conformance_test.exs` hardcoded only `OfficeGraph.WorkGraph.Domain` and seven `OfficeGraph.WorkGraph.Resources.*` modules, while `openspec/changes/first-backend-walking-skeleton/specs/walking-skeleton-persistence/spec.md` only required "stable walking-loop product records" to be Ash-backed. The broader design specs already say Ash owns stable resources, actions, policies, and bounded-context lifecycle rules, but that was not made machine-checkable for every implemented table.

Current inventory:

- `40` migration-created tables.
- `40` manual `use Ecto.Schema` modules under `lib/office_graph`.
- `7` Ash resources, all in `lib/office_graph/work_graph/resources`.
- Those `7` Ash resources duplicate existing WorkGraph Ecto schema modules instead of replacing them.

## Non-Negotiable End State

- No `use Ecto.Schema` remains under `lib/office_graph`.
- No table-backed manual `changeset/2` model modules remain under `lib/office_graph`.
- Every implemented durable table has exactly one canonical Ash resource module in its owning context.
- Every Ash domain is registered in `config :office_graph, :ash_domains`.
- Every Ash resource is registered in exactly one owning Ash domain.
- `lib/office_graph/work_graph/resources/*.ex` is removed; WorkGraph resources live at `OfficeGraph.WorkGraph.Signal`, `OfficeGraph.WorkGraph.Task`, and so on.
- Direct `Repo.insert`, `Repo.update`, `Repo.delete`, schema-based `Repo.get_by`, and `Ecto.Multi.insert/update/delete` paths are removed from normal model mutations.
- Remaining direct Ecto usage is limited to transaction boundaries or explicitly documented read/maintenance exceptions, with no manual schema definitions.
- `./bin/verify-backend`, `mix architecture.conformance`, `openspec validate repair-ash-model-conformance --strict`, and `openspec validate --changes --strict` pass from inside the Nix shell.

## Subagent And Commit Rules

- Use only `gpt-5.5` subagents with `reasoning_effort: xhigh`.
- Prefer one worker per milestone. Do not let two workers edit the same context files at once.
- Use read-only reviewer subagents after high-risk milestones: WorkGraph convergence, foundation domains, and final conformance.
- Commit at every milestone listed below. Do not stack multiple milestones into one commit.
- Run project verification through the project Nix shell; every task below
  spells out the exact command to run.

## Resource Ownership Inventory

The conformance test will use this table as the required model inventory.

| Table | Domain | Canonical Ash Resource |
| --- | --- | --- |
| `organizations` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Organization` |
| `workspaces` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Workspace` |
| `initiatives` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Initiative` |
| `workstreams` | `OfficeGraph.Tenancy.Domain` | `OfficeGraph.Tenancy.Workstream` |
| `principals` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.Principal` |
| `principal_profiles` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.PrincipalProfile` |
| `credentials` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.Credential` |
| `sessions` | `OfficeGraph.Identity.Domain` | `OfficeGraph.Identity.Session` |
| `capabilities` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.Capability` |
| `roles` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.Role` |
| `role_capabilities` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.RoleCapability` |
| `role_assignments` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.RoleAssignment` |
| `policy_bundles` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.PolicyBundle` |
| `authorization_decisions` | `OfficeGraph.Authorization.Domain` | `OfficeGraph.Authorization.AuthorizationDecision` |
| `operation_correlations` | `OfficeGraph.Operations.Domain` | `OfficeGraph.Operations.OperationCorrelation` |
| `audit_records` | `OfficeGraph.Audit.Domain` | `OfficeGraph.Audit.AuditRecord` |
| `revisions` | `OfficeGraph.Revisions.Domain` | `OfficeGraph.Revisions.Revision` |
| `tombstones` | `OfficeGraph.Tombstones.Domain` | `OfficeGraph.Tombstones.Tombstone` |
| `documents` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.Document` |
| `document_blocks` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentBlock` |
| `document_marks` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentMark` |
| `document_references` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentReference` |
| `document_revisions` | `OfficeGraph.Content.Domain` | `OfficeGraph.Content.DocumentRevision` |
| `external_sources` | `OfficeGraph.Integrations.Domain` | `OfficeGraph.Integrations.ExternalSource` |
| `raw_archives` | `OfficeGraph.Integrations.Domain` | `OfficeGraph.Integrations.RawArchive` |
| `normalized_intake_events` | `OfficeGraph.Integrations.Domain` | `OfficeGraph.Integrations.NormalizedIntakeEvent` |
| `external_references` | `OfficeGraph.ExternalRefs.Domain` | `OfficeGraph.ExternalRefs.ExternalReference` |
| `graph_items` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.GraphItem` |
| `graph_relationships` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.GraphRelationship` |
| `signals` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Signal` |
| `tasks` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Task` |
| `review_findings` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.ReviewFinding` |
| `verification_checks` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.VerificationCheck` |
| `artifacts` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.Artifact` |
| `evidence_items` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.EvidenceItem` |
| `verification_results` | `OfficeGraph.WorkGraph.Domain` | `OfficeGraph.WorkGraph.VerificationResult` |
| `work_packets` | `OfficeGraph.WorkPackets.Domain` | `OfficeGraph.WorkPackets.WorkPacket` |
| `runs` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.Run` |
| `run_events` | `OfficeGraph.Runs.Domain` | `OfficeGraph.Runs.RunEvent` |
| `proposed_graph_changes` | `OfficeGraph.ProposedChanges.Domain` | `OfficeGraph.ProposedChanges.ProposedGraphChange` |

## File Map

- Create OpenSpec corrective change:
  - `openspec/changes/repair-ash-model-conformance/proposal.md`
  - `openspec/changes/repair-ash-model-conformance/design.md`
  - `openspec/changes/repair-ash-model-conformance/tasks.md`
  - `openspec/changes/repair-ash-model-conformance/specs/backend-model-ownership/spec.md`
  - `openspec/changes/repair-ash-model-conformance/model-inventory.md`
- Modify architecture gate:
  - `test/office_graph/architecture/ash_conformance_test.exs`
  - `mix.exs`
  - `bin/verify-backend`
- Create domains:
  - `lib/office_graph/tenancy/domain.ex`
  - `lib/office_graph/identity/domain.ex`
  - `lib/office_graph/authorization/domain.ex`
  - `lib/office_graph/operations/domain.ex`
  - `lib/office_graph/audit/domain.ex`
  - `lib/office_graph/revisions/domain.ex`
  - `lib/office_graph/tombstones/domain.ex`
  - `lib/office_graph/content/domain.ex`
  - `lib/office_graph/integrations/domain.ex`
  - `lib/office_graph/external_refs/domain.ex`
  - `lib/office_graph/work_packets/domain.ex`
  - `lib/office_graph/runs/domain.ex`
  - `lib/office_graph/proposed_changes/domain.ex`
- Modify existing domain:
  - `lib/office_graph/work_graph/domain.ex`
  - `config/config.exs`
- Convert existing model modules from Ecto schemas to Ash resources:
  - every canonical resource listed in the inventory table above
- Delete duplicate resource modules:
  - `lib/office_graph/work_graph/resources/artifact.ex`
  - `lib/office_graph/work_graph/resources/evidence_item.ex`
  - `lib/office_graph/work_graph/resources/review_finding.ex`
  - `lib/office_graph/work_graph/resources/signal.ex`
  - `lib/office_graph/work_graph/resources/task.ex`
  - `lib/office_graph/work_graph/resources/verification_check.ex`
  - `lib/office_graph/work_graph/resources/verification_result.ex`
- Modify contexts to call Ash actions instead of schema changesets:
  - `lib/office_graph/tenancy.ex`
  - `lib/office_graph/identity.ex`
  - `lib/office_graph/authorization.ex`
  - `lib/office_graph/operations.ex`
  - `lib/office_graph/audit.ex`
  - `lib/office_graph/revisions.ex`
  - `lib/office_graph/content.ex`
  - `lib/office_graph/integrations.ex`
  - `lib/office_graph/proposed_changes.ex`
  - `lib/office_graph/work_graph.ex`
  - `lib/office_graph/work_graph/changes/validate_same_scope_references.ex`
- Modify tests using schema changesets or direct schema inserts:
  - `test/office_graph/foundation/bootstrap_test.exs`
  - `test/office_graph/proposed_changes/proposed_changes_test.exs`
  - `test/office_graph/work_graph/ash_authorization_test.exs`
  - `test/office_graph/work_graph/persistence_test.exs`
  - `test/office_graph/work_graph/walking_skeleton_test.exs`
  - `test/office_graph_web/api_smoke_test.exs`
- Replace exception ledger:
  - `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md`
  - `openspec/changes/first-backend-walking-skeleton/implementation-summary.md`

## Shared Ash Resource Pattern

Each canonical resource module uses this shape. This example is complete for
`OfficeGraph.Tenancy.Organization`; the later tasks list the exact table,
fields, and identities for the other resources in each context.

```elixir
defmodule OfficeGraph.Tenancy.Organization do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Tenancy.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  identities do
    identity :unique_slug, [:slug]
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:id, :name, :slug]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end
end
```

Adjustments:

- Scope-bearing resources with `organization_id` and `workspace_id` must include read policies that filter to `actor(:organization_id)` and `actor(:workspace_id)`.
- Organization-scoped resources without `workspace_id` must filter to `actor(:organization_id)`.
- Bootstrap-only actions run through public context functions and may use `authorize?: false` internally until the identity/authorization administration flows exist.
- Append-only trace resources expose `create` and `read`; they do not expose generic update/delete actions.
- Lifecycle resources expose named update actions only, for example `mark_satisfied`, `mark_verified_complete`, `reject`, and `mark_applied`.
- Do not add Ash-generated migrations in this repair. Keep `migrate? false` and preserve the existing migrations.

---

## Task 1: Add The Corrective OpenSpec Change

**Files:**
- Create: `openspec/changes/repair-ash-model-conformance/proposal.md`
- Create: `openspec/changes/repair-ash-model-conformance/design.md`
- Create: `openspec/changes/repair-ash-model-conformance/tasks.md`
- Create: `openspec/changes/repair-ash-model-conformance/specs/backend-model-ownership/spec.md`
- Create: `openspec/changes/repair-ash-model-conformance/model-inventory.md`

- [ ] **Step 1: Create `proposal.md`**

```markdown
# Repair Ash Model Conformance

## Why

The first backend walking skeleton added Ash resources only for a subset of
WorkGraph records and left all table-backed model modules as manual Ecto
schemas. That creates duplicate validation surfaces and lets future
implementation drift away from the architecture decision that Ash owns stable
resources, actions, lifecycle rules, and authorization-aware policy surfaces.

## What Changes

- Promote every implemented durable table to a canonical Ash resource in its
  owning bounded-context domain.
- Remove duplicate WorkGraph `Resources.*` Ash modules and make the existing
  model modules the resource modules.
- Remove table-backed `use Ecto.Schema` modules from `lib/office_graph`.
- Convert context writes and reads from schema changesets/direct `Repo`
  mutations to Ash actions.
- Expand architecture conformance so all migration-created tables, Ash
  domains, resources, and direct Ecto exceptions are machine-checked.

## Impact

- Affects all backend model modules under `lib/office_graph`.
- Does not change existing database migrations except where a test exposes a
  real table mismatch.
- Keeps direct Ecto only for approved transaction/read/maintenance escape
  hatches with no manual model schemas.
```

- [ ] **Step 2: Create `design.md`**

```markdown
# Design

## Canonical Resource Modules

The existing model module path is the canonical Ash resource path. For example,
`OfficeGraph.WorkGraph.Signal` is the Ash resource for `signals`; the parallel
`OfficeGraph.WorkGraph.Resources.Signal` module is removed. This keeps public
context code, test structs, and future GraphQL/interface code from choosing
between two definitions of the same table.

## Existing Migrations Stay Authoritative

The repair uses AshPostgres resources with `migrate? false` because the current
two migrations already create the walking-skeleton tables. Follow-on changes can
move selected tables to Ash-owned migrations intentionally, but this repair is
about model ownership and conformance rather than schema churn.

## Direct Ecto Boundary

Direct Ecto may remain for explicit transactions, performance-sensitive reads,
maintenance, replay scans, or raw SQL that Ash does not express cleanly. Direct
Ecto must not define table-backed schemas or bypass normal domain mutations.
Every remaining direct path is documented in the architecture exception ledger.

## Authorization

This repair preserves the existing walking-skeleton authorization behavior and
makes scope-aware Ash policies mandatory for resources that carry organization
or workspace scope. Bootstrap and trace append paths may use internal
`authorize?: false` calls only through owning context functions until their
administration flows are implemented.
```

- [ ] **Step 3: Create `specs/backend-model-ownership/spec.md`**

```markdown
## ADDED Requirements

### Requirement: Durable Model Ash Ownership
Every durable table implemented by Office Graph SHALL have a canonical Ash
resource in the bounded context that owns its lifecycle.

#### Scenario: A migration-created table is implemented
- **WHEN** a table exists in a committed migration for the backend
- **THEN** the table MUST be represented by exactly one canonical Ash resource
  module registered in exactly one owning Ash domain

#### Scenario: A table-backed model module exists
- **WHEN** production code under `lib/office_graph` defines a durable model
- **THEN** it MUST use `Ash.Resource` with `AshPostgres.DataLayer` rather than
  `Ecto.Schema`

#### Scenario: An existing model is promoted
- **WHEN** an existing manual Ecto schema is promoted to Ash
- **THEN** the existing canonical module path MUST become the Ash resource
  unless an OpenSpec design explicitly approves a different public module path

### Requirement: No Duplicate Model Definitions
Office Graph SHALL avoid parallel model definitions for the same durable table.

#### Scenario: A table has an Ash resource
- **WHEN** a table is represented by an Ash resource
- **THEN** production code MUST NOT also define a manual Ecto schema for that
  table

#### Scenario: WorkGraph resources are converged
- **WHEN** WorkGraph typed resources are Ash-backed
- **THEN** they MUST be defined as `OfficeGraph.WorkGraph.Signal`,
  `OfficeGraph.WorkGraph.Task`, `OfficeGraph.WorkGraph.ReviewFinding`,
  `OfficeGraph.WorkGraph.VerificationCheck`,
  `OfficeGraph.WorkGraph.Artifact`, `OfficeGraph.WorkGraph.EvidenceItem`, and
  `OfficeGraph.WorkGraph.VerificationResult` rather than parallel
  `OfficeGraph.WorkGraph.Resources.*` modules

### Requirement: Direct Ecto Exception Control
Office Graph SHALL keep direct Ecto outside normal model ownership and normal
domain mutations.

#### Scenario: Direct Ecto remains useful
- **WHEN** a context uses direct Ecto for a transaction boundary, read model,
  replay scan, bulk maintenance path, or raw SQL escape hatch
- **THEN** that path MUST be listed in the architecture exception ledger with
  its owner, reason, allowed operation type, approving spec, and retirement
  condition

#### Scenario: A normal mutation is implemented
- **WHEN** production code creates, updates, or deletes a durable domain record
- **THEN** it MUST call the owning context command or Ash action rather than
  `Repo.insert`, `Repo.update`, `Repo.delete`, or schema changesets

### Requirement: Architecture Gate Covers Model Ownership
The backend verification gate SHALL fail when implementation and model
ownership specs diverge.

#### Scenario: Backend verification runs
- **WHEN** `mix architecture.conformance` or `./bin/verify-backend` runs
- **THEN** it MUST verify table inventory, Ash domain registration, Ash resource
  registration, absence of table-backed Ecto schemas, absence of duplicate
  model definitions, and direct Ecto exception ledger coverage
```

- [ ] **Step 4: Create `model-inventory.md`**

Copy the full "Resource Ownership Inventory" table from this plan into
`openspec/changes/repair-ash-model-conformance/model-inventory.md`.

- [ ] **Step 5: Create `tasks.md`**

```markdown
## 1. OpenSpec And Gate Setup

- [ ] 1.1 Add this corrective OpenSpec change and model inventory.
- [ ] 1.2 Replace the WorkGraph-only architecture conformance test with a
  repo-wide model ownership gate.
- [ ] 1.3 Commit the failing conformance gate before converting models.

## 2. WorkGraph Convergence

- [ ] 2.1 Convert canonical WorkGraph modules to Ash resources.
- [ ] 2.2 Register graph identity, graph relationships, and typed resources in
  `OfficeGraph.WorkGraph.Domain`.
- [ ] 2.3 Replace WorkGraph reads, reference validation, and tests with
  canonical Ash resource modules.
- [ ] 2.4 Delete `OfficeGraph.WorkGraph.Resources.*` modules.

## 3. Foundation Domains

- [ ] 3.1 Convert Tenancy resources and bootstrap writes to Ash.
- [ ] 3.2 Convert Identity resources and bootstrap writes to Ash.
- [ ] 3.3 Convert Authorization resources and bootstrap writes to Ash.

## 4. Traceability, Content, Intake, And Runtime Domains

- [ ] 4.1 Convert Operations, Audit, Revisions, and Tombstones resources.
- [ ] 4.2 Convert Content resources and `create_plain_document/3`.
- [ ] 4.3 Convert Integrations and ExternalRefs resources and manual intake
  storage.
- [ ] 4.4 Convert ProposedChanges resources and state transitions.
- [ ] 4.5 Convert WorkPackets and Runs resources.

## 5. Final Conformance

- [ ] 5.1 Remove all `use Ecto.Schema` occurrences under `lib/office_graph`.
- [ ] 5.2 Shrink the architecture exception ledger to remaining direct Ecto
  transaction/read paths only.
- [ ] 5.3 Run full backend and OpenSpec verification.
- [ ] 5.4 Commit final docs and evidence.
```

- [ ] **Step 6: Validate and commit OpenSpec correction**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate repair-ash-model-conformance --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
git add openspec/changes/repair-ash-model-conformance
git commit -m "docs: add Ash model conformance change"
```

Expected: both OpenSpec commands pass.

## Task 2: Replace The WorkGraph-Only Gate With A Repo-Wide Failing Gate

**Files:**
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`
- Modify: `mix.exs`
- Modify: `bin/verify-backend`

- [ ] **Step 1: Replace hardcoded WorkGraph resource lists with full inventory**

In `test/office_graph/architecture/ash_conformance_test.exs`, define:

```elixir
@expected_resources %{
  "organizations" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Organization},
  "workspaces" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Workspace},
  "initiatives" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Initiative},
  "workstreams" => {OfficeGraph.Tenancy.Domain, OfficeGraph.Tenancy.Workstream},
  "principals" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.Principal},
  "principal_profiles" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.PrincipalProfile},
  "credentials" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.Credential},
  "sessions" => {OfficeGraph.Identity.Domain, OfficeGraph.Identity.Session},
  "capabilities" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.Capability},
  "roles" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.Role},
  "role_capabilities" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.RoleCapability},
  "role_assignments" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.RoleAssignment},
  "policy_bundles" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.PolicyBundle},
  "authorization_decisions" => {OfficeGraph.Authorization.Domain, OfficeGraph.Authorization.AuthorizationDecision},
  "operation_correlations" => {OfficeGraph.Operations.Domain, OfficeGraph.Operations.OperationCorrelation},
  "audit_records" => {OfficeGraph.Audit.Domain, OfficeGraph.Audit.AuditRecord},
  "revisions" => {OfficeGraph.Revisions.Domain, OfficeGraph.Revisions.Revision},
  "tombstones" => {OfficeGraph.Tombstones.Domain, OfficeGraph.Tombstones.Tombstone},
  "documents" => {OfficeGraph.Content.Domain, OfficeGraph.Content.Document},
  "document_blocks" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentBlock},
  "document_marks" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentMark},
  "document_references" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentReference},
  "document_revisions" => {OfficeGraph.Content.Domain, OfficeGraph.Content.DocumentRevision},
  "external_sources" => {OfficeGraph.Integrations.Domain, OfficeGraph.Integrations.ExternalSource},
  "raw_archives" => {OfficeGraph.Integrations.Domain, OfficeGraph.Integrations.RawArchive},
  "normalized_intake_events" => {OfficeGraph.Integrations.Domain, OfficeGraph.Integrations.NormalizedIntakeEvent},
  "external_references" => {OfficeGraph.ExternalRefs.Domain, OfficeGraph.ExternalRefs.ExternalReference},
  "graph_items" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.GraphItem},
  "graph_relationships" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.GraphRelationship},
  "signals" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Signal},
  "tasks" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Task},
  "review_findings" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.ReviewFinding},
  "verification_checks" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.VerificationCheck},
  "artifacts" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.Artifact},
  "evidence_items" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.EvidenceItem},
  "verification_results" => {OfficeGraph.WorkGraph.Domain, OfficeGraph.WorkGraph.VerificationResult},
  "work_packets" => {OfficeGraph.WorkPackets.Domain, OfficeGraph.WorkPackets.WorkPacket},
  "runs" => {OfficeGraph.Runs.Domain, OfficeGraph.Runs.Run},
  "run_events" => {OfficeGraph.Runs.Domain, OfficeGraph.Runs.RunEvent},
  "proposed_graph_changes" => {OfficeGraph.ProposedChanges.Domain, OfficeGraph.ProposedChanges.ProposedGraphChange}
}
```

- [ ] **Step 2: Add model ownership tests**

Add tests that assert:

```elixir
test "every migration-created table has exactly one expected Ash resource" do
  assert migration_tables() == Map.keys(@expected_resources) |> Enum.sort()
end

test "all expected domains are registered" do
  registered = Application.compile_env(:office_graph, :ash_domains, []) |> MapSet.new()

  expected =
    @expected_resources
    |> Map.values()
    |> Enum.map(fn {domain, _resource} -> domain end)
    |> MapSet.new()

  assert MapSet.subset?(expected, registered)
end

test "all expected resources are AshPostgres resources with existing migrations as source" do
  for {table, {domain, resource}} <- @expected_resources do
    assert Code.ensure_loaded?(domain)
    assert Code.ensure_loaded?(resource)
    assert Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer
    assert AshPostgres.DataLayer.Info.table(resource) == table
    refute AshPostgres.DataLayer.Info.migrate?(resource)
  end
end

test "each expected resource is registered in exactly one owning domain" do
  domain_resources =
    @expected_resources
    |> Map.values()
    |> Enum.map(fn {domain, _resource} -> domain end)
    |> Enum.uniq()
    |> Map.new(fn domain -> {domain, Ash.Domain.Info.resources(domain)} end)

  for {_table, {expected_domain, resource}} <- @expected_resources do
    owners =
      domain_resources
      |> Enum.filter(fn {_domain, resources} -> resource in resources end)
      |> Enum.map(fn {domain, _resources} -> domain end)

    assert owners == [expected_domain]
  end
end

test "production model code does not define manual Ecto schemas" do
  offenders =
    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.filter(fn path -> File.read!(path) =~ "use Ecto.Schema" end)

  assert offenders == []
end

test "WorkGraph no longer has parallel Resources modules" do
  assert Path.wildcard("lib/office_graph/work_graph/resources/*.ex") == []
end
```

Implement `migration_tables/0` in the same test with the migration filenames already present:

```elixir
defp migration_tables do
  "priv/repo/migrations/*.exs"
  |> Path.wildcard()
  |> Enum.flat_map(fn path ->
    Regex.scan(~r/create\s+table\(:([a-zA-Z0-9_]+)/, File.read!(path), capture: :all_but_first)
  end)
  |> List.flatten()
  |> Enum.sort()
end
```

- [ ] **Step 3: Keep direct Ecto tests but make them stricter**

Adjust the existing direct mutation scan so `Repo.transaction` may be ledgered, but `Repo.insert`, `Repo.update`, `Repo.delete`, `Repo.get_by` plus schema-based `Ecto.Multi.insert/update/delete` fail unless listed in the new ledger. The expected failing state should include current context writes.

- [ ] **Step 4: Run and commit the failing gate**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/architecture/ash_conformance_test.exs
git add test/office_graph/architecture/ash_conformance_test.exs mix.exs bin/verify-backend
git commit -m "test: require repo-wide Ash model ownership"
```

Expected before conversion: the test fails on missing domains/resources, existing `use Ecto.Schema`, and `work_graph/resources/*.ex`.

## Task 3: Converge WorkGraph On Canonical Ash Resources

**Files:**
- Modify: `lib/office_graph/work_graph/domain.ex`
- Modify: `lib/office_graph/work_graph/graph_item.ex`
- Modify: `lib/office_graph/work_graph/graph_relationship.ex`
- Modify: `lib/office_graph/work_graph/signal.ex`
- Modify: `lib/office_graph/work_graph/task.ex`
- Modify: `lib/office_graph/work_graph/review_finding.ex`
- Modify: `lib/office_graph/work_graph/verification_check.ex`
- Modify: `lib/office_graph/work_graph/artifact.ex`
- Modify: `lib/office_graph/work_graph/evidence_item.ex`
- Modify: `lib/office_graph/work_graph/verification_result.ex`
- Modify: `lib/office_graph/work_graph.ex`
- Modify: `lib/office_graph/work_graph/changes/validate_same_scope_references.ex`
- Delete: `lib/office_graph/work_graph/resources/*.ex`
- Modify tests under `test/office_graph/work_graph/`

- [ ] **Step 1: Convert `OfficeGraph.WorkGraph.Signal` to Ash**

Replace `lib/office_graph/work_graph/signal.ex` with the Ash resource definition currently represented by `OfficeGraph.WorkGraph.Resources.Signal`, but set:

```elixir
defmodule OfficeGraph.WorkGraph.Signal do
  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]
end
```

Keep the existing attributes, `postgres table "signals"`, policies, JSON API type, GraphQL type, and same-scope reference validation.

- [ ] **Step 2: Convert remaining WorkGraph typed resources**

For each old `OfficeGraph.WorkGraph.Resources.*` module, move its Ash definition into the canonical module:

| Old module | New module | Table |
| --- | --- | --- |
| `OfficeGraph.WorkGraph.Resources.Task` | `OfficeGraph.WorkGraph.Task` | `tasks` |
| `OfficeGraph.WorkGraph.Resources.ReviewFinding` | `OfficeGraph.WorkGraph.ReviewFinding` | `review_findings` |
| `OfficeGraph.WorkGraph.Resources.VerificationCheck` | `OfficeGraph.WorkGraph.VerificationCheck` | `verification_checks` |
| `OfficeGraph.WorkGraph.Resources.Artifact` | `OfficeGraph.WorkGraph.Artifact` | `artifacts` |
| `OfficeGraph.WorkGraph.Resources.EvidenceItem` | `OfficeGraph.WorkGraph.EvidenceItem` | `evidence_items` |
| `OfficeGraph.WorkGraph.Resources.VerificationResult` | `OfficeGraph.WorkGraph.VerificationResult` | `verification_results` |

Remove each old `use Ecto.Schema`, `import Ecto.Changeset`, and `changeset/2` from the canonical module.

- [ ] **Step 3: Add graph identity resources**

Convert:

- `OfficeGraph.WorkGraph.GraphItem` for `graph_items`.
- `OfficeGraph.WorkGraph.GraphRelationship` for `graph_relationships`.

Required actions:

- `GraphItem`: `read`, `create`; identity on `[:resource_type, :resource_id]`.
- `GraphRelationship`: `read`, `create`; identity on `[:source_item_id, :target_item_id, :relationship_type]`.

- [ ] **Step 4: Register canonical resources**

Replace the resource list in `lib/office_graph/work_graph/domain.ex` with:

```elixir
resources do
  resource OfficeGraph.WorkGraph.GraphItem
  resource OfficeGraph.WorkGraph.GraphRelationship
  resource OfficeGraph.WorkGraph.Signal
  resource OfficeGraph.WorkGraph.Task
  resource OfficeGraph.WorkGraph.ReviewFinding
  resource OfficeGraph.WorkGraph.VerificationCheck
  resource OfficeGraph.WorkGraph.Artifact
  resource OfficeGraph.WorkGraph.EvidenceItem
  resource OfficeGraph.WorkGraph.VerificationResult
end
```

- [ ] **Step 5: Replace references to `OfficeGraph.WorkGraph.Resources.*`**

Update `lib/office_graph/work_graph.ex`, `test/office_graph/architecture/ash_conformance_test.exs`, and WorkGraph tests to reference canonical modules.

- [ ] **Step 6: Replace same-scope validation Ecto reads**

In `lib/office_graph/work_graph/changes/validate_same_scope_references.ex`, replace `Repo.get(schema, id)` against Ecto schemas with an Ash read helper:

```elixir
defp fetch_reference(resource, record_id) do
  resource
  |> Ash.Query.filter(id == ^record_id)
  |> Ash.read_one(authorize?: false)
end
```

When the reference includes graph identity constraints, fetch the graph item through `OfficeGraph.WorkGraph.GraphItem` and compare `resource_type` and `resource_id`.

- [ ] **Step 7: Delete duplicate resource files**

Delete every file under `lib/office_graph/work_graph/resources/`.

- [ ] **Step 8: Verify and commit WorkGraph convergence**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph test/office_graph/architecture/ash_conformance_test.exs
git add lib/office_graph/work_graph test/office_graph/work_graph test/office_graph/architecture/ash_conformance_test.exs
git add -u lib/office_graph/work_graph/resources
git commit -m "refactor: converge WorkGraph models on Ash"
```

Expected: WorkGraph tests pass or only fail on non-WorkGraph model ownership still pending in the architecture test.

## Task 4: Convert Tenancy, Identity, And Authorization Domains

**Files:**
- Create: `lib/office_graph/tenancy/domain.ex`
- Create: `lib/office_graph/identity/domain.ex`
- Create: `lib/office_graph/authorization/domain.ex`
- Modify: `lib/office_graph/tenancy/*.ex`
- Modify: `lib/office_graph/identity/*.ex`
- Modify: `lib/office_graph/authorization/*.ex`
- Modify: `lib/office_graph/tenancy.ex`
- Modify: `lib/office_graph/identity.ex`
- Modify: `lib/office_graph/authorization.ex`
- Modify: `config/config.exs`
- Modify: bootstrap and authorization tests

- [ ] **Step 1: Add domain modules**

Create:

```elixir
defmodule OfficeGraph.Tenancy.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Tenancy.Organization
    resource OfficeGraph.Tenancy.Workspace
    resource OfficeGraph.Tenancy.Initiative
    resource OfficeGraph.Tenancy.Workstream
  end
end
```

```elixir
defmodule OfficeGraph.Identity.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Identity.Principal
    resource OfficeGraph.Identity.PrincipalProfile
    resource OfficeGraph.Identity.Credential
    resource OfficeGraph.Identity.Session
  end
end
```

```elixir
defmodule OfficeGraph.Authorization.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Authorization.Capability
    resource OfficeGraph.Authorization.Role
    resource OfficeGraph.Authorization.RoleCapability
    resource OfficeGraph.Authorization.RoleAssignment
    resource OfficeGraph.Authorization.PolicyBundle
    resource OfficeGraph.Authorization.AuthorizationDecision
  end
end
```

- [ ] **Step 2: Convert model modules**

Convert the fourteen model modules in these contexts to Ash resources using the shared pattern and existing table fields.

Required identities:

- `Organization`: `:slug`
- `Workspace`: `[:organization_id, :slug]`
- `Initiative`: `[:workspace_id, :slug]`
- `Workstream`: `[:initiative_id, :slug]`
- `Principal`: `:email`
- `PrincipalProfile`: `:principal_id`
- `Credential`: `[:provider, :subject]`
- `Session`: `[:principal_id, :organization_id, :workspace_id, :purpose]`
- `Capability`: `:key`
- `Role`: `[:organization_id, :key]`
- `RoleCapability`: `[:role_id, :capability_id]`
- `RoleAssignment`: `[:principal_id, :role_id, :organization_id]`
- `PolicyBundle`: `[:organization_id, :version]`
- `AuthorizationDecision`: no unique identity in the current migration.

- [ ] **Step 3: Replace bootstrap get-or-insert helpers**

Replace private Ecto helpers with an Ash helper local to each context:

```elixir
defp get_or_create!(resource, lookup, attrs) do
  case Ash.get!(resource, Map.new(lookup), authorize?: false) do
    nil -> Ash.create!(resource, attrs, authorize?: false)
    record -> record
  end
end
```

`Ash.get!/3` accepts primary-key values and identity maps; every `lookup`
listed in this task must match the resource identity declared in Step 2.

- [ ] **Step 4: Register domains**

Update `config/config.exs`:

```elixir
config :office_graph,
  ash_domains: [
    OfficeGraph.Tenancy.Domain,
    OfficeGraph.Identity.Domain,
    OfficeGraph.Authorization.Domain,
    OfficeGraph.WorkGraph.Domain
  ],
  ecto_repos: [OfficeGraph.Repo],
  generators: [timestamp_type: :utc_datetime]
```

- [ ] **Step 5: Verify and commit foundation domains**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/foundation/bootstrap_test.exs test/office_graph/work_graph/ash_authorization_test.exs test/office_graph/architecture/ash_conformance_test.exs
git add lib/office_graph/tenancy lib/office_graph/identity lib/office_graph/authorization config/config.exs test/office_graph/foundation test/office_graph/work_graph test/office_graph/architecture
git commit -m "feat: add Ash foundation domains"
```

Expected: bootstrap and authorization behavior remains unchanged; architecture test still fails only for contexts not yet converted.

## Task 5: Convert Traceability Domains

**Files:**
- Create: `lib/office_graph/operations/domain.ex`
- Create: `lib/office_graph/audit/domain.ex`
- Create: `lib/office_graph/revisions/domain.ex`
- Create: `lib/office_graph/tombstones/domain.ex`
- Modify: `lib/office_graph/operations/operation_correlation.ex`
- Modify: `lib/office_graph/audit/audit_record.ex`
- Modify: `lib/office_graph/revisions/revision.ex`
- Modify: `lib/office_graph/tombstones/tombstone.ex`
- Modify: `lib/office_graph/operations.ex`
- Modify: `lib/office_graph/audit.ex`
- Modify: `lib/office_graph/revisions.ex`
- Modify: `config/config.exs`

- [ ] **Step 1: Add domain modules**

Create one domain per context:

```elixir
defmodule OfficeGraph.Operations.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Operations.OperationCorrelation
  end
end
```

Repeat the same domain shape for:

- `OfficeGraph.Audit.Domain` with `OfficeGraph.Audit.AuditRecord`.
- `OfficeGraph.Revisions.Domain` with `OfficeGraph.Revisions.Revision`.
- `OfficeGraph.Tombstones.Domain` with `OfficeGraph.Tombstones.Tombstone`.

- [ ] **Step 2: Convert resources**

Convert these append-only resources with `read` and `create` actions:

- `OperationCorrelation`: identity on `:correlation_id`.
- `AuditRecord`: no unique identity.
- `Revision`: no unique identity; indexed lookup remains `resource_type/resource_id`.
- `Tombstone`: identity on `[:resource_type, :resource_id]`.

- [ ] **Step 3: Replace context inserts**

Replace:

- `OfficeGraph.Operations.start_operation/3`
- `OfficeGraph.Audit.record!/5`
- `OfficeGraph.Revisions.record!/5`

with `Ash.create!` calls against the owning resource. Keep return values and errors compatible with current tests.

- [ ] **Step 4: Register domains and verify**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/walking_skeleton_test.exs test/office_graph/architecture/ash_conformance_test.exs
git add lib/office_graph/operations lib/office_graph/audit lib/office_graph/revisions lib/office_graph/tombstones config/config.exs test/office_graph
git commit -m "feat: add Ash traceability domains"
```

Expected: walking skeleton traceability assertions still pass; architecture failures shrink to content, integration, proposed-change, work-packet, and run contexts.

## Task 6: Convert Content, Integrations, And External References

**Files:**
- Create: `lib/office_graph/content/domain.ex`
- Create: `lib/office_graph/integrations/domain.ex`
- Create: `lib/office_graph/external_refs/domain.ex`
- Modify: `lib/office_graph/content/*.ex`
- Modify: `lib/office_graph/integrations/*.ex`
- Modify: `lib/office_graph/external_refs/external_reference.ex`
- Modify: `lib/office_graph/content.ex`
- Modify: `lib/office_graph/integrations.ex`
- Modify: `config/config.exs`

- [ ] **Step 1: Add domains**

Create:

- `OfficeGraph.Content.Domain` with `Document`, `DocumentBlock`, `DocumentMark`, `DocumentReference`, `DocumentRevision`.
- `OfficeGraph.Integrations.Domain` with `ExternalSource`, `RawArchive`, `NormalizedIntakeEvent`.
- `OfficeGraph.ExternalRefs.Domain` with `ExternalReference`.

- [ ] **Step 2: Convert resources**

Required identities:

- `Document`: no unique identity.
- `DocumentBlock`: `[:document_id, :position]`.
- `DocumentMark`: no unique identity.
- `DocumentReference`: no unique identity.
- `DocumentRevision`: `[:document_id, :revision_number]`.
- `ExternalSource`: `:key`.
- `RawArchive`: no unique identity; indexed lookup remains `[:source_id, :content_hash]`.
- `NormalizedIntakeEvent`: no unique identity; indexed lookup remains `[:source_identity, :replay_identity]`.
- `ExternalReference`: `[:source_id, :external_id]`.

- [ ] **Step 3: Replace content document creation**

Rewrite `OfficeGraph.Content.create_plain_document/3` so it uses Ash creates inside the same transaction boundary:

```elixir
Repo.transaction(fn ->
  document = Ash.create!(Document, document_attrs, authorize?: false)
  _block = Ash.create!(DocumentBlock, block_attrs, authorize?: false)
  _revision = Ash.create!(DocumentRevision, revision_attrs, authorize?: false)
  document
end)
```

The context may keep `Repo.transaction/1`; it must not use `Ecto.Multi.insert` or schema changesets.

- [ ] **Step 4: Replace manual intake storage**

Rewrite `OfficeGraph.Integrations.record_manual_intake/3` so:

- `ExternalSource` lookup/create uses Ash.
- Duplicate normalized event lookup uses Ash read against `NormalizedIntakeEvent`.
- `RawArchive` creation uses Ash.
- `NormalizedIntakeEvent` creation uses Ash.

- [ ] **Step 5: Register domains, verify, and commit**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/work_graph/walking_skeleton_test.exs test/office_graph_web/api_smoke_test.exs test/office_graph/architecture/ash_conformance_test.exs
git add lib/office_graph/content lib/office_graph/integrations lib/office_graph/external_refs config/config.exs test/office_graph test/office_graph_web
git commit -m "feat: add Ash content and intake domains"
```

Expected: manual intake, document creation, and API smoke behavior remains unchanged.

## Task 7: Convert Proposed Changes, Work Packets, And Runs

**Files:**
- Create: `lib/office_graph/proposed_changes/domain.ex`
- Create: `lib/office_graph/work_packets/domain.ex`
- Create: `lib/office_graph/runs/domain.ex`
- Modify: `lib/office_graph/proposed_changes/proposed_graph_change.ex`
- Modify: `lib/office_graph/work_packets/work_packet.ex`
- Modify: `lib/office_graph/runs/run.ex`
- Modify: `lib/office_graph/runs/run_event.ex`
- Modify: `lib/office_graph/proposed_changes.ex`
- Modify: `config/config.exs`
- Modify: `test/office_graph/proposed_changes/proposed_changes_test.exs`

- [ ] **Step 1: Add domains**

Create:

- `OfficeGraph.ProposedChanges.Domain` with `OfficeGraph.ProposedChanges.ProposedGraphChange`.
- `OfficeGraph.WorkPackets.Domain` with `OfficeGraph.WorkPackets.WorkPacket`.
- `OfficeGraph.Runs.Domain` with `OfficeGraph.Runs.Run` and `OfficeGraph.Runs.RunEvent`.

- [ ] **Step 2: Convert resources**

Resources:

- `ProposedGraphChange`: fields from `proposed_graph_changes`, actions `read`, `create`, `reject`, `mark_applied`.
- `WorkPacket`: fields `organization_id`, `workspace_id`, `title`, `state`, actions `read`, `create`.
- `Run`: fields from `runs`, actions `read`, `create`.
- `RunEvent`: fields from `run_events`, actions `read`, `create`.

- [ ] **Step 3: Replace proposed-change writes**

Rewrite:

- `create_for_manual_intake/4` to create `ProposedGraphChange` through Ash.
- `reject!/2` to use `Ash.update!` with the `reject` action.
- `mark_applied!/1` to use `Ash.update!` with the `mark_applied` action.
- `get_many!/1` to use an Ash read query.

- [ ] **Step 4: Register domains, verify, and commit**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix test test/office_graph/proposed_changes test/office_graph/work_graph test/office_graph/architecture/ash_conformance_test.exs
git add lib/office_graph/proposed_changes lib/office_graph/work_packets lib/office_graph/runs config/config.exs test/office_graph
git commit -m "feat: add Ash runtime and proposed-change domains"
```

Expected: proposed-change behavior remains unchanged; architecture conformance should now fail only on stale exception-ledger/docs if any.

## Task 8: Remove Manual Ecto Model Surface And Shrink Exceptions

**Files:**
- Modify: `openspec/changes/first-backend-walking-skeleton/architecture-exceptions.md`
- Modify: `openspec/changes/first-backend-walking-skeleton/implementation-summary.md`
- Modify: `openspec/changes/repair-ash-model-conformance/tasks.md`
- Modify: `test/office_graph/architecture/ash_conformance_test.exs`

- [ ] **Step 1: Verify no manual schema remains**

Run:

```bash
rg -n "use Ecto\\.Schema|import Ecto\\.Changeset|def changeset" lib/office_graph
```

Expected: no output for table-backed models.

- [ ] **Step 2: Shrink direct Ecto exception ledger**

Replace the existing function-heavy ledger with entries only for remaining direct Ecto transaction/read paths. Each row must include:

```markdown
| File | Function | Operation type | Reason | Approving spec | Retirement condition |
| --- | --- | --- | --- | --- | --- |
```

The final ledger must not approve any table-backed manual schema definitions.

- [ ] **Step 3: Update implementation summary**

Add a short evidence section that includes:

- `40/40` migration-created tables have canonical Ash resources.
- `0` production Ecto schema modules remain.
- `0` WorkGraph `Resources.*` duplicate modules remain.
- All Ash domains are registered in `config/config.exs`.
- `mix architecture.conformance` is in `./bin/verify-backend`.

- [ ] **Step 4: Mark corrective tasks complete**

Update `openspec/changes/repair-ash-model-conformance/tasks.md` as each item is completed.

- [ ] **Step 5: Verify and commit docs/gate cleanup**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix architecture.conformance
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate repair-ash-model-conformance --strict
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate --changes --strict
git add openspec test/office_graph/architecture/ash_conformance_test.exs
git commit -m "docs: document repo-wide Ash conformance"
```

Expected: all three commands pass.

## Task 9: Full Verification And Final Review

**Files:**
- Any remaining files changed by earlier tasks.

- [ ] **Step 1: Run full backend verification**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command ./bin/verify-backend
```

Expected:

- compile with warnings-as-errors passes.
- format check passes.
- boundary check passes.
- architecture conformance passes.
- test suite passes.

- [ ] **Step 2: Run final search checks**

Run:

```bash
rg -n "use Ecto\\.Schema|OfficeGraph\\.WorkGraph\\.Resources|Repo\\.(insert!?|update!?|delete!?|get_by)|Ecto\\.Multi\\.(insert|update|delete)" lib/office_graph test
```

Expected:

- no `use Ecto.Schema`.
- no `OfficeGraph.WorkGraph.Resources`.
- no unledgered direct mutations.
- tests may use Ash helpers or public contexts, not schema changesets.

- [ ] **Step 3: Dispatch final read-only review subagents**

Use two `gpt-5.5` / `xhigh` reviewers:

- Reviewer 1: code quality and behavior preservation across converted contexts.
- Reviewer 2: OpenSpec and architecture conformance coverage.

Fix any valid findings in new commits before final handoff.

- [ ] **Step 4: Commit final fixups**

Run:

```bash
git status --short
git add lib config test openspec mix.exs bin/verify-backend
git commit -m "chore: finalize repo-wide Ash model conformance"
```

Expected: final working tree is clean after the commit.

## Acceptance Checklist

- [ ] `openspec list` shows `repair-ash-model-conformance` as the active corrective change until reviewed.
- [ ] `openspec validate repair-ash-model-conformance --strict` passes.
- [ ] `openspec validate --changes --strict` passes.
- [ ] `mix architecture.conformance` passes.
- [ ] `./bin/verify-backend` passes.
- [ ] `rg -n "use Ecto\\.Schema" lib/office_graph` returns no output.
- [ ] `rg -n "OfficeGraph\\.WorkGraph\\.Resources" lib test` returns no output.
- [ ] Every table in `priv/repo/migrations/*.exs` is represented in the resource ownership inventory.
- [ ] Every Ash resource in the inventory is registered in exactly one owning Ash domain.
- [ ] The exception ledger contains no table-backed schema exceptions.
