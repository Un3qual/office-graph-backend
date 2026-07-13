# Durable Work Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add transaction-safe Oban jobs, typed domain events, observable failure handling, and authorized projection invalidation, then exercise the boundary from manual intake.

**Architecture:** Product commands record a typed domain-event row and unique Oban dispatch job inside the owning Repo transaction. A thin worker loads the event through `OfficeGraph.DurableDelivery`, classifies failures, and publishes a scope-authorized identity/version invalidation through Phoenix PubSub; Postgres projections remain authoritative.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Phoenix 1.8, Ash 3, Ecto/Postgres, Oban 2.x, Phoenix PubSub, ExUnit, Telemetry, OpenSpec, Nix.

## Global Constraints

- Use the project Nix flake for every runtime and CLI command.
- Keep Postgres as durable truth and PubSub messages as invalidation hints only.
- Use typed relational columns for event identity, scope, correlation, state, and failure classification; do not add a generic JSON event payload.
- Keep Oban workers, PubSub handlers, and API entrypoints thin and fail closed.
- Preserve tenant/workspace authorization, operation correlation, command replay, and transaction rollback semantics.
- Do not add a provider integration, agent runtime, frontend socket store, Redis, Kafka, RabbitMQ, or Tailwind.

---

### Task 1: Oban Runtime And Typed Persistence

**Files:**
- Modify: `mix.exs`
- Modify: `mix.lock`
- Modify: `config/config.exs`
- Modify: `config/test.exs`
- Modify: `lib/office_graph/application.ex`
- Create: `priv/repo/migrations/20260712090000_add_oban_jobs.exs`
- Create: `priv/repo/migrations/20260712090500_create_domain_events.exs`
- Test: `test/office_graph/durable_delivery/runtime_test.exs`

**Interfaces:**
- Produces: supervised `Oban` instance named `Oban`, queues `delivery: 10`, `integrations: 5`, and `agents: 5`; test mode `:manual`.
- Produces: `domain_events` columns `id`, `organization_id`, `workspace_id`, `operation_id`, `causation_event_id`, `event_key`, `event_kind`, `subject_kind`, `subject_id`, `subject_version`, `delivery_state`, `failure_code`, `occurred_at`, `dispatched_at`, `failed_at`, and timestamps.

- [ ] Write `runtime_test.exs` assertions for configured Repo/queues/test mode, supervised Oban child spec, required domain-event columns, foreign keys, uniqueness, and indexes.
- [ ] Run `mix test test/office_graph/durable_delivery/runtime_test.exs`; confirm failure because Oban and the migrations do not exist.
- [ ] Add `{:oban, "~> 2.20"}` to `deps/0`, fetch through Nix, and inspect the installed official migration/config API before writing migrations.
- [ ] Add explicit Oban config and supervision; keep tests in manual mode with queues/plugins disabled.
- [ ] Generate the standard Oban migration and create the typed domain-event migration with unique `event_key` plus scope, operation, subject, state, and occurred-time indexes.
- [ ] Run migrations and the focused runtime test; confirm green.
- [ ] Commit with `feat: add durable delivery runtime`.

### Task 2: Transactional Event And Job Contract

**Files:**
- Create: `lib/office_graph/durable_delivery.ex`
- Create: `lib/office_graph/durable_delivery/domain.ex`
- Create: `lib/office_graph/durable_delivery/domain_event.ex`
- Create: `lib/office_graph/durable_delivery/event_request.ex`
- Create: `lib/office_graph/durable_delivery/dispatch_event_worker.ex`
- Modify: `lib/office_graph.ex`
- Modify: `config/config.exs`
- Test: `test/office_graph/durable_delivery/event_test.exs`

**Interfaces:**
- Consumes: `%OfficeGraph.Identity.SessionContext{}` and `%OfficeGraph.Operations.OperationCorrelation{}`.
- Produces: `DurableDelivery.record_and_enqueue(session, operation, attrs) :: {:ok, DomainEvent.t()} | {:error, term()}`.
- `attrs` requires `event_key`, `event_kind`, `subject_kind`, `subject_id`; accepts `subject_version`, `causation_event_id`, and `occurred_at`.
- Produces: `DispatchEventWorker.new(%{"event_id" => id, "organization_id" => org, "workspace_id" => workspace}, unique: [fields: [:worker, :args], period: :infinity])`.

- [ ] Write event tests for valid creation, invalid/mismatched session-operation scope, malformed event/subject kinds, replay returning one event/job, and outer transaction rollback leaving neither event nor job.
- [ ] Run the focused tests and confirm missing-module failures.
- [ ] Implement the private Ash resource/action and context validation. Insert the event and Oban job through the same Repo transaction without opening a nested independent transaction.
- [ ] Use the event row's stable id and typed scope in job args; never place product bodies or raw metadata in args.
- [ ] Rerun the event tests and architecture compiler with warnings as errors.
- [ ] Commit with `feat: add transactional domain events`.

### Task 3: Worker Classification And Terminal Visibility

**Files:**
- Create: `lib/office_graph/durable_delivery/worker_result.ex`
- Create: `lib/office_graph/durable_delivery/test_worker.ex`
- Create: `lib/office_graph/durable_delivery/terminal_job.ex`
- Modify: `lib/office_graph/durable_delivery.ex`
- Modify: `lib/office_graph/durable_delivery/dispatch_event_worker.ex`
- Modify: `lib/office_graph/authorization.ex`
- Test: `test/office_graph/durable_delivery/worker_test.exs`
- Test: `test/office_graph/durable_delivery/terminal_jobs_test.exs`
- Test: `test/office_graph/foundation/bootstrap_test.exs`

**Interfaces:**
- Produces: `WorkerResult.normalize(:ok | {:error, {:retryable, code}} | {:error, {:terminal, code}})` mapped to Oban success/error/cancel results.
- Produces: `DurableDelivery.list_terminal_jobs(session, limit: integer()) :: {:ok, [TerminalJob.t()]} | {:error, :forbidden}`.
- `TerminalJob` exposes only id, worker, queue, state, attempt, max_attempts, failure_code, attempted_at, cancelled_at, and discarded_at.

- [ ] Write failing worker tests for success, retryable failure, terminal cancellation, attempt exhaustion, safe failure codes, and idempotent already-delivered behavior.
- [ ] Write failing terminal-job tests proving organization/workspace filtering, bounded limits, stable ordering, and omission of args/errors/stack traces.
- [ ] Add `durable_delivery.read` to owner bootstrap and authorization tests.
- [ ] Implement one shared result classifier and the deterministic test worker; use Oban's supported return values rather than custom retry loops.
- [ ] Implement the scoped terminal query over Oban jobs using typed scope args and safe summaries.
- [ ] Rerun worker, terminal-job, bootstrap, and authorization tests.
- [ ] Commit with `feat: expose durable work failures`.

### Task 4: Authorized Projection Invalidation And Telemetry

**Files:**
- Create: `lib/office_graph/durable_delivery/projection_invalidation.ex`
- Create: `lib/office_graph/durable_delivery/subscriptions.ex`
- Create: `lib/office_graph/durable_delivery/telemetry.ex`
- Modify: `lib/office_graph/durable_delivery/dispatch_event_worker.ex`
- Modify: `lib/office_graph_web/telemetry.ex`
- Test: `test/office_graph/durable_delivery/projection_invalidation_test.exs`
- Test: `test/office_graph/durable_delivery/telemetry_test.exs`

**Interfaces:**
- Produces: `%ProjectionInvalidation{event_id, event_kind, subject_kind, subject_id, subject_version, operation_id, organization_id, workspace_id}`.
- Produces: `DurableDelivery.subscribe(session, organization_id, workspace_id) :: :ok | {:error, :forbidden}`.
- Produces: `DurableDelivery.dispatch(event_id) :: :ok | {:error, retry_or_terminal_reason}`.
- Topic format is internal and derived only by `Subscriptions`; callers cannot supply arbitrary topic strings.

- [ ] Write failing subscription tests for same-scope delivery, cross-organization/workspace denial, current-session validation, envelope field limits, and no subject body.
- [ ] Write failing dispatch tests proving publish occurs after event load, successful delivery marks the event, and replay does not rebroadcast.
- [ ] Write telemetry tests that attach to Oban lifecycle events and assert worker/queue/state/attempt/duration while rejecting args and tenant identifiers.
- [ ] Implement the envelope, authorization check using `Authorization.authorize_projection/3`, internal PubSub topics, atomic pending-to-dispatched transition, and safe idempotent replay.
- [ ] Add Oban job metrics to the existing telemetry list and attach any custom handler under supervision.
- [ ] Rerun invalidation and telemetry tests.
- [ ] Commit with `feat: publish authorized projection invalidations`.

### Task 5: Manual Intake Consumer

**Files:**
- Modify: `lib/office_graph/integrations.ex`
- Modify: `lib/office_graph.ex` or boundary declarations needed for the one-way dependency
- Modify: `openspec/specs/backend-model-ownership/architecture-exceptions.md`
- Test: `test/office_graph/integrations/durable_delivery_test.exs`
- Test: `test/office_graph/integrations/concurrency_test.exs`
- Test: `test/office_graph_web/operator_commands_graphql_test.exs`
- Test: `test/office_graph_web/operator_commands_json_test.exs`

**Interfaces:**
- Consumes: `DurableDelivery.record_and_enqueue/3` inside the accepted-intake transaction.
- Event key: `manual-intake:<normalized_event_id>:accepted`.
- Event kind: `manual_intake.accepted`; subject kind: `normalized_intake_event`; subject id: normalized event id.

- [ ] Write failing integration tests asserting one event/job for first acceptance, none for duplicate intake, stable replay without a second event/job, and full rollback if event creation is forced to fail.
- [ ] Run the focused integration and transport tests; confirm the new event assertions fail.
- [ ] Add the DurableDelivery dependency to Integrations and record the event after proposed changes are created but before the transaction commits.
- [ ] Preserve the existing intake return shape and ensure command replay reads do not enqueue again.
- [ ] Rerun integration concurrency, GraphQL, JSON, and architecture tests.
- [ ] Commit with `feat: deliver manual intake events durably`.

### Task 6: Verify, Sync, And Archive

**Files:**
- Modify: `openspec/changes/add-durable-work-delivery/tasks.md`
- Modify/Create: durable specs named by the change deltas
- Move: `openspec/changes/add-durable-work-delivery/` to `openspec/changes/archive/2026-07-12-add-durable-work-delivery/`
- Move: this plan to `docs/superpowers/plans/archive/`
- Modify: `docs/superpowers/plans/README.md`

- [ ] Run every focused test from Tasks 1-5 plus architecture conformance and migration reset.
- [ ] Run `openspec validate add-durable-work-delivery --strict`, `mix verify`, and `git diff --check` in the Nix shell.
- [ ] Map every requirement/scenario to implementation and tests; fix any critical or warning-level gap.
- [ ] Sync all four delta specs into durable specs idempotently and validate all durable specs.
- [ ] Mark all tasks complete, archive the change and plan, confirm `openspec list --json` is empty, and rerun strict validation.
- [ ] Commit with `chore: archive durable work delivery`, push `codex/archive-operator-command-loop`, and verify PR #21 contains the new commits.
