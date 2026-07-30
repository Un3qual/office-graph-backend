# Migration Rebaseline Inventory

## Scope

The replaced unreleased chain contained 49 tracked files: 48 migrations and
the migration formatter configuration. The reviewed database-boundary
inventory assigned 173 repository-authored SQL occurrences to this change:

- 72 `migration.check` expressions;
- 64 `migration.execute` calls; and
- 37 `migration.where` predicates.

The prior PostgreSQL 18 UUIDv7 fragment was an approved exception and was not
part of the 173 removal-debt occurrences.

The strengthened terminal scanner also identifies SQL application-data
literals inside migration `execute` calls. Against the Git-preserved old chain
it finds four non-MD5 `INSERT INTO` literals and 22 MD5-bearing literals. Those
26 signals overlap the 64 execute calls; they are not additional historical
debt rows.

## Disposition Rules

Every removed occurrence has one of these terminal owners:

- enum, format, positive-number, scope, and lifecycle checks are owned by
  typed Ash attributes, constraints, validations, accepted actions, and atomic
  transitions;
- nullable-key predicates are owned by ordinary identities or
  `nils_distinct?: false` identities;
- active, accepted, pending, and unrevoked predicates are owned by private
  typed identity-slot attributes maintained by the owning actions;
- intermediate DDL, backfills, rehashes, and index replacement execute calls
  are obsolete because the logical baseline creates only the terminal schema;
- canonical application records are owned by idempotent Ash setup actions;
- Oban's tables, enum, triggers, and indexes remain owned by
  `Oban.Migrations`, while `StoredJob` is an explicitly non-migrating Ash read
  model; and
- the one retained repository-authored SQL occurrence is the separately
  approved and fingerprinted native `uuidv7()` default.

## Per-File SQL Inventory

Counts below reproduce the 173-entry reviewed debt inventory. Each row maps
all occurrences in that file to its terminal owner.

| Replaced migration | Check | Where | Execute | Terminal disposition |
|---|---:|---:|---:|---|
| `20260621000649_create_identity_tenancy_bootstrap` | 0 | 3 | 5 | Terminal Identity/Tenancy resources, ordinary or nil-aware identities, and AshPostgres `match_with` composite references replace bootstrap DDL, tenant-scope foreign-key SQL, and scoped predicates. |
| `20260621001247_create_walking_skeleton_persistence` | 0 | 3 | 0 | Operation, intake replay, and proposal identities replace nullable and accepted-only predicates. |
| `20260622224500_make_sessions_unique_by_active_context` | 0 | 1 | 0 | `Session.active_identity_slot` owns live-session uniqueness. |
| `20260624181500_create_work_packet_run_verification_slice` | 0 | 4 | 0 | Ordinary nullable identities and current WorkPacket/Run relationships own replay and optional-link uniqueness. |
| `20260624224500_add_unique_operation_indexes_for_packet_run_verification` | 0 | 3 | 0 | Ordinary operation and acceptance identities replace non-null predicates. |
| `20260711000500_add_packet_version_titles` | 0 | 0 | 1 | The terminal `WorkPacketVersion` snapshot creates the current title column directly. |
| `20260711001000_allow_waived_verification_results` | 0 | 0 | 3 | Typed verification-result attributes and actions create the terminal waived-result model directly. |
| `20260712090500_create_domain_events` | 2 | 0 | 0 | Typed delivery state and positive subject-version constraints are enforced by the DomainEvent resource and actions. |
| `20260712091000_backfill_durable_delivery_owner_capability` | 0 | 0 | 2 | Capability creation moves to the Authorization catalog; owner-role grants are reconciled through the Ash owner-role action. |
| `20260713100000_create_relationship_registry` | 4 | 1 | 2 | Typed relationship-definition attributes, the definition identity, and the WorkGraph reference catalog replace checks, active filtering, and inserted registry rows. |
| `20260713101000_type_graph_relationships` | 2 | 1 | 8 | Terminal typed relationships and lifecycle actions replace intermediate column rewrites, backfills, lifecycle checks, and active filtering. |
| `20260713103000_harden_relationship_policy_constraints` | 3 | 0 | 0 | RelationshipDefinition constraints and WorkGraph policy validation own provenance, authorization, and cycle policy. |
| `20260713104000_enforce_graph_relationship_validity_start` | 1 | 0 | 0 | Accepted relationship actions own validity timestamps. |
| `20260714090000_add_system_operation_delivery` | 9 | 2 | 14 | Terminal OperationCorrelation and DomainEvent resources own scope variants, typed state, nullability, and system idempotency; capability data moves to Authorization setup. |
| `20260714091000_create_software_proving_resources` | 4 | 0 | 0 | Provider/resource typed constraints own sync, lifecycle, and non-negative sequence rules. |
| `20260714092000_create_github_installation_bindings` | 8 | 0 | 2 | GitHub resource constraints own installation state and positive identifiers; capability/grant rows move to Ash setup and role reconciliation. |
| `20260714093000_add_provider_delivery_archives` | 1 | 1 | 2 | RawArchive typed kind plus its ordinary provider-delivery identity replace the check and predicate; capability rows move to setup. |
| `20260714094000_create_github_sync_outcomes` | 2 | 0 | 0 | SyncOutcome typed state and provider-sequence constraints own both checks. |
| `20260714095000_create_github_outbound_actions` | 2 | 0 | 0 | OutboundAction typed action/state constraints own both checks; its separate historical capability insertions move to setup. |
| `20260714110000_harden_github_integration_scoping` | 1 | 7 | 1 | Nil-aware scoped identities and typed scope relationships replace split organization/workspace indexes and the backfill. |
| `20260715143000_scope_system_operation_idempotency` | 0 | 1 | 0 | Separate nullable-slot `OperationCorrelation` identities own organization- and workspace-scoped system replay uniqueness without constraining human operations. |
| `20260717060000_scope_github_check_runs_to_pull_requests` | 0 | 2 | 1 | The nil-aware GitHub check-run identity and terminal pull-request relationship replace the backfill and split indexes. |
| `20260720120000_create_agent_runtime_foundation` | 27 | 2 | 1 | Typed AgentRuntime resources/actions own formats, enums, budgets, versions, modes, and visibility; pending identities use typed slots; the canonical run-review definition moves to AgentRuntime setup. |
| `20260720121000_backfill_agent_runtime_capabilities` | 0 | 0 | 1 | Authorization setup owns capability rows and role actions own grants. |
| `20260721180000_add_agent_execution_leases` | 0 | 0 | 3 | Terminal lease attributes/actions replace DDL/backfill; Authorization setup and role actions own capability/grant data. |
| `20260721210000_add_agent_runtime_governed_outputs` | 0 | 5 | 4 | Ordinary nullable identities and terminal relationships replace output predicates and schema rewrites; canonical capability data moves to setup. |
| `20260721230000_backfill_agent_runtime_governance` | 0 | 0 | 3 | Terminal governance attributes/actions replace the backfill; capability/grant data moves to setup. |
| `20260722040000_harden_agent_runtime_snapshot_lineage` | 0 | 0 | 5 | Current AuthoritySnapshot/ContextEntry attributes and creation actions replace legacy rehashes, defaults, and nullability rewrites. |
| `20260724200000_harden_run_index_storage` | 0 | 0 | 1 | The generated terminal run index replaces handwritten index storage changes. |
| `20260724210000_add_runs_scope_index` | 0 | 0 | 2 | The generated terminal run index replaces concurrent create/drop SQL. |
| `20260725120000_add_human_session_foundation` | 6 | 1 | 1 | Typed principal/link/session/login attributes and validations own state rules; `Session.active_identity_slot` owns the active predicate and the AuthenticationEvent `match_with` reference preserves workspace/organization scope. |
| `20260725233500_add_principals_normalized_email_index` | 0 | 0 | 2 | The current Principal identity and generated index replace handwritten expression-index SQL. |

## Application-Data Insert Inventory

All historical application inserts target exactly five resource categories:

| Historical target | Terminal owner |
|---|---|
| `capabilities` | `OfficeGraph.Authorization` recognized-capability manifest and `Capability.setup_catalog` |
| `role_capabilities` | Authorization owner/system role setup actions using Ash identities and upserts |
| `relationship_definitions` | `OfficeGraph.WorkGraph.ReferenceCatalog.definitions/0` and `RelationshipDefinition.ensure` |
| `relationship_endpoint_rules` | `OfficeGraph.WorkGraph.ReferenceCatalog.rules/0` and `RelationshipEndpointRule.ensure` |
| `agent_definitions` | `OfficeGraph.AgentRuntime.ReferenceCatalog.definitions/0` and `AgentDefinition.ensure` |

`OfficeGraph.Release.setup/0` composes those owning boundaries. Fresh-database
verification runs it twice and asserts the exact manifests without duplicates.

## MD5 Disposition

MD5 was not being used for passwords, signatures, or another cryptographic
security decision. The old SQL truncated the MD5 digest of stable strings such
as `office_graph:capability:<key>` or
`office_graph:role_capability:<role-id>:<key>` into UUID-shaped identifiers so
replayed data migrations would choose the same primary key.

That choice was still inappropriate: it coupled persistent IDs to an ad hoc
string format, hid application-data ownership inside schema SQL, bypassed the
project's PostgreSQL UUIDv7 strategy, and made ordinary identity/upsert
semantics harder to see. The terminal setup actions match records by declared
Ash identities and let PostgreSQL 18 generate UUIDv7 primary keys.

## Terminal Evidence

- Generated baseline:
  `priv/repo/migrations/20260729233957_initial.exs`
- Current snapshots: `priv/resource_snapshots/repo/<table>/*.json`
- Removal debt: zero files and zero occurrences
- Approved SQL: one fingerprinted `fragment("uuidv7()")`
- Empty PostgreSQL 18 migration: passed
- Release setup first run and replay: passed
- Complete rollback and re-application: passed
