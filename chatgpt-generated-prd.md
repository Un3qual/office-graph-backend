# PRD: Backend for Agent-Ready Work Graph Platform

## 1. Product Summary

Build the backend for a graph-based work planning system designed for human-agent software teams.

The product ingests software-development signals such as Sentry issues, GitHub issues, CI failures, pull requests, and manually entered goals. It converts them into a typed work graph consisting of signals, tasks, questions, decisions, checks, artifacts, evidence, and agent runs.

The system’s core purpose is to turn ambiguous work into structured, agent-ready work packets with context, constraints, success criteria, autonomy policies, and verification evidence.

This backend will be built with:

- Elixir
- Phoenix
- Absinthe GraphQL API
- React frontend consuming GraphQL
- Postgres for durable persistence
- Phoenix PubSub, Channels, OTP, Registry, DynamicSupervisor, GenServers, Tasks, and distributed Erlang for realtime/concurrent/distributed behavior
- No LiveView
- No Redis
- No Postgres-backed PubSub or realtime coordination
- Postgres is allowed for durable persistence, transactional state, audit trails, and optionally durable job queues

---

## 2. Product Goals

### 2.1 Primary Goal

Create a backend that acts as the system of record and orchestration layer for a human-agent work graph.

The backend must support:

1. Organizations, users, teams, roles, and permissions.
2. A typed graph of work nodes and semantic edges.
3. Ingestion from external developer tools.
4. AI-generated graph mutation proposals.
5. Human approval and editing of generated graph changes.
6. Question queues for resolving ambiguity.
7. Agent-readiness scoring.
8. Work packet compilation.
9. Agent/human handoff.
10. Realtime updates to React clients.
11. Verification and evidence tracking.

### 2.2 MVP Product Thesis

The MVP should prove:

> Messy engineering signals can be converted into structured, agent-ready work packets more effectively than a normal issue tracker.

### 2.3 Non-Goals for MVP

Do not build:

- Full Jira/Linear replacement.
- Full visual graph editor.
- Built-in coding agent runtime.
- Built-in CI runner.
- Built-in observability product.
- LiveView UI.
- Redis-backed queues, PubSub, locks, or presence.
- Complex distributed workflow engine.
- Full enterprise SSO unless needed by first customers.
- Multi-region deployment.
- Custom vector database unless necessary.

---

## 3. Target User Workflows

### 3.1 Import a Sentry Issue

User connects Sentry and imports an issue.

Backend should:

1. Store the raw external event.
2. Normalize it into an internal `Signal` node.
3. Attach stack trace, event metadata, affected release, and links as artifacts.
4. Trigger AI triage.
5. Generate a proposed graph patch.
6. Create suggested task, question, check, and evidence nodes.
7. Score agent readiness.
8. Publish realtime updates to subscribed clients.

Example result:

```text
Signal: Sentry issue #4921
Task: Fix OAuth callback crash
Question: Should invalid OAuth state redirect or return 400?
Check: Regression test covers invalid OAuth state
Artifact: Stack trace
Artifact: Affected release
Readiness: Needs human answer
```

---

### 3.2 Answer a Blocking Question

User opens the Question Queue and answers a question.

Backend should:

1. Create a `Decision` node.
2. Link decision to question using an `answers` edge.
3. Mark question as answered.
4. Recalculate readiness for blocked tasks.
5. Recompile affected work packets.
6. Publish realtime updates.

---

### 3.3 Generate a Work Packet

User opens a task and requests a work packet.

Backend should compile:

- Objective
- Context
- Relevant artifacts
- Linked decisions
- Blocking assumptions
- Constraints
- Autonomy policy
- Success criteria
- Escalation rules
- Suggested execution mode

The work packet should be renderable as Markdown and JSON.

---

### 3.4 Send Work to Human or Agent

User selects an execution handoff mode.

Supported MVP handoff targets:

- Copy Markdown work packet.
- Create GitHub issue.
- Create Linear issue.
- Create local task bundle via CLI.
- Mark task as assigned to human.
- Mark task as ready for external agent.

The MVP does not need to run an autonomous coding agent internally.

---

### 3.5 Track Verification Evidence

After a PR opens, CI runs, or a Sentry issue quiets down, backend should ingest new external events and link them as evidence.

Example:

```text
Task: Fix OAuth callback crash
  validated_by -> Check: Regression test passes
  evidence_for -> GitHub PR #914 merged
  evidence_for -> GitHub Actions run passed
  evidence_for -> Sentry issue has no new events for 24h
```

Task status should move toward `verified` only when required checks pass or are waived by an authorized human.

---

## 4. Backend Architecture

### 4.1 High-Level Architecture

```text
React Frontend
  |
  | GraphQL queries/mutations/subscriptions
  v
Phoenix + Absinthe API
  |
  | domain calls
  v
Application Contexts
  |
  | transactional writes
  v
Postgres
  |
  | events/jobs
  v
Oban / durable workers
  |
  | async processing
  v
AI Pipelines + Integration Adapters

Realtime:
Domain Events -> Phoenix PubSub -> Absinthe Subscriptions / Phoenix Channels -> React
```

---

### 4.2 Backend Runtime Principles

Use OTP for:

- Realtime PubSub.
- Per-run process supervision.
- Temporary in-memory run state.
- Node-local and cluster-wide process discovery.
- Concurrent external API syncs.
- Bounded parallel AI calls.
- Webhook processing fanout.
- Presence and online collaboration state.
- Ephemeral locks where safe.

Use Postgres for:

- Durable graph state.
- Durable audit trail.
- Durable external events.
- Durable artifacts.
- Durable run records.
- Durable job queue if using Oban.
- Durable idempotency keys.
- Durable integration configuration.

Do not use Postgres for:

- Realtime PubSub.
- User presence.
- Live collaboration fanout.
- Ephemeral locks.
- High-frequency transient run updates.
- In-memory agent-run state.

Do not use Redis for MVP.

---

## 5. Elixir/Phoenix Application Structure

Suggested umbrella or single-app modular structure:

```text
lib/work_graph/
  accounts/
  orgs/
  auth/
  permissions/

  graph/
    node.ex
    edge.ex
    graph_patch.ex
    graph_service.ex
    traversal.ex
    projections.ex

  signals/
  questions/
  decisions/
  tasks/
  checks/
  artifacts/
  evidence/
  work_packets/
  runs/

  integrations/
    github/
    sentry/
    linear/
    common/

  ingestion/
    external_event.ex
    normalizer.ex
    processor.ex

  ai/
    provider.ex
    prompt.ex
    pipelines/
      triage.ex
      graph_patch_generator.ex
      question_generator.ex
      readiness_scorer.ex
      work_packet_compiler.ex

  execution/
    handoff.ex
    local_bundle.ex
    github_issue_handoff.ex
    linear_issue_handoff.ex

  verification/
    verifier.ex
    github_verifier.ex
    sentry_verifier.ex

  realtime/
    topic.ex
    publisher.ex
    presence.ex

  jobs/
    process_external_event_job.ex
    generate_graph_patch_job.ex
    score_readiness_job.ex
    compile_work_packet_job.ex
    sync_github_job.ex
    sync_sentry_job.ex
    verify_task_job.ex

lib/work_graph_web/
  router.ex
  endpoint.ex

  graphql/
    schema.ex
    middleware/
    resolvers/
    dataloaders/
    types/
    mutations/
    queries/
    subscriptions/

  channels/
    user_socket.ex
    org_channel.ex
    run_channel.ex
```

---

## 6. Core Domain Model

### 6.1 Node Types

MVP node types:

```text
signal
task
question
decision
check
artifact
evidence
run
```

Future node types:

```text
goal
requirement
plan
milestone
risk
feature
team
project
```

### 6.2 Edge Types

MVP edge types:

```text
generated_from
raises
answers
blocked_by
depends_on
requires
validates
produced
evidence_for
duplicates
relates_to
assigned_to
```

### 6.3 Node Statuses

#### Signal Status

```text
new
triaged
converted
ignored
duplicate
archived
```

#### Question Status

```text
open
answered
superseded
dismissed
archived
```

#### Task Status

```text
draft
needs_context
needs_human_answer
ready_for_agent
ready_for_human
in_execution
needs_review
monitoring
verified
failed
archived
```

#### Check Status

```text
pending
running
passed
failed
waived
```

#### Run Status

```text
created
queued
in_progress
blocked
completed
failed
cancelled
```

---

## 7. Database Schema

### 7.1 Organizations

```sql
CREATE TABLE organizations (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  settings JSONB NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

### 7.2 Users

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  avatar_url TEXT,
  settings JSONB NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

### 7.3 Organization Memberships

```sql
CREATE TABLE organization_memberships (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  user_id UUID NOT NULL REFERENCES users(id),
  role TEXT NOT NULL,
  permissions JSONB NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id)
);
```

---

### 7.4 Nodes

```sql
CREATE TABLE nodes (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL,
  risk_level TEXT,
  readiness_score INTEGER,
  properties JSONB NOT NULL DEFAULT '{}',
  created_by_type TEXT NOT NULL,
  created_by_id TEXT,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Indexes:

```sql
CREATE INDEX nodes_org_type_status_idx
ON nodes (organization_id, type, status);

CREATE INDEX nodes_org_updated_idx
ON nodes (organization_id, updated_at DESC);

CREATE INDEX nodes_properties_gin_idx
ON nodes USING GIN (properties);
```

---

### 7.5 Edges

```sql
CREATE TABLE edges (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  from_node_id UUID NOT NULL REFERENCES nodes(id),
  to_node_id UUID NOT NULL REFERENCES nodes(id),
  type TEXT NOT NULL,
  properties JSONB NOT NULL DEFAULT '{}',
  confidence FLOAT,
  created_by_type TEXT NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Indexes:

```sql
CREATE INDEX edges_from_type_idx
ON edges (from_node_id, type);

CREATE INDEX edges_to_type_idx
ON edges (to_node_id, type);

CREATE INDEX edges_org_type_idx
ON edges (organization_id, type);
```

---

### 7.6 External Events

```sql
CREATE TABLE external_events (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  integration_id UUID,
  source TEXT NOT NULL,
  source_event_type TEXT NOT NULL,
  external_id TEXT,
  payload_hash TEXT NOT NULL,
  payload JSONB NOT NULL,
  occurred_at TIMESTAMPTZ,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  processing_status TEXT NOT NULL DEFAULT 'new',
  error TEXT,
  UNIQUE (organization_id, source, source_event_type, payload_hash)
);
```

Purpose:

- Store all inbound webhooks and synced events.
- Provide idempotency.
- Allow replay.
- Provide debugging and auditability.

---

### 7.7 Artifacts

```sql
CREATE TABLE artifacts (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  source TEXT NOT NULL,
  external_id TEXT,
  artifact_type TEXT NOT NULL,
  title TEXT,
  url TEXT,
  content TEXT,
  content_ref TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Artifact types:

```text
sentry_issue
stack_trace
github_issue
github_pr
github_commit
github_check_run
ci_log
linear_issue
markdown_packet
local_bundle
user_note
```

---

### 7.8 Node Artifacts

```sql
CREATE TABLE node_artifacts (
  node_id UUID NOT NULL REFERENCES nodes(id),
  artifact_id UUID NOT NULL REFERENCES artifacts(id),
  relationship TEXT NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (node_id, artifact_id, relationship)
);
```

Relationships:

```text
source
context
evidence
output
reference
```

---

### 7.9 Node Events / Audit Trail

```sql
CREATE TABLE node_events (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  node_id UUID REFERENCES nodes(id),
  event_type TEXT NOT NULL,
  actor_type TEXT NOT NULL,
  actor_id TEXT,
  payload JSONB NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Actor types:

```text
user
ai
system
integration
agent
```

---

### 7.10 Graph Patches

```sql
CREATE TABLE graph_patches (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  source_event_id UUID REFERENCES external_events(id),
  status TEXT NOT NULL,
  reason TEXT,
  confidence FLOAT,
  proposed_by_type TEXT NOT NULL,
  proposed_by_id TEXT,
  patch JSONB NOT NULL,
  validation_errors JSONB NOT NULL DEFAULT '[]',
  applied_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Statuses:

```text
proposed
validated
needs_human_review
applied
rejected
failed
```

---

### 7.11 Work Packets

```sql
CREATE TABLE work_packets (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  task_node_id UUID NOT NULL REFERENCES nodes(id),
  version INTEGER NOT NULL,
  status TEXT NOT NULL,
  markdown TEXT NOT NULL,
  json JSONB NOT NULL,
  compiled_from_hash TEXT NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_node_id, version)
);
```

Statuses:

```text
draft
current
superseded
archived
```

---

### 7.12 Runs

```sql
CREATE TABLE runs (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  target_node_id UUID NOT NULL REFERENCES nodes(id),
  run_type TEXT NOT NULL,
  status TEXT NOT NULL,
  executor_type TEXT NOT NULL,
  executor_id TEXT,
  autonomy_policy JSONB NOT NULL DEFAULT '{}',
  result JSONB NOT NULL DEFAULT '{}',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Run types:

```text
human_handoff
local_bundle
github_issue_handoff
linear_issue_handoff
external_agent_handoff
internal_agent_future
```

---

### 7.13 Run Events

```sql
CREATE TABLE run_events (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  run_id UUID NOT NULL REFERENCES runs(id),
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Purpose:

- Durable timeline for agent/human handoff.
- Realtime updates are broadcast from this stream.
- Clients can reconnect and reload durable run history.

---

## 8. Graph Patch System

### 8.1 Rationale

AI should not mutate the graph directly.

AI should emit a `GraphPatch`. The application validates the patch before applying it.

### 8.2 GraphPatch Shape

```json
{
  "reason": "Sentry issue indicates a production OAuth crash",
  "confidence": 0.86,
  "operations": [
    {
      "op": "create_node",
      "temp_id": "task_1",
      "node_type": "task",
      "title": "Fix OAuth callback crash",
      "description": "Handle invalid OAuth state without throwing 500.",
      "status": "needs_human_answer",
      "properties": {
        "risk_level": "medium"
      }
    },
    {
      "op": "create_node",
      "temp_id": "question_1",
      "node_type": "question",
      "title": "Should invalid OAuth state redirect or return 400?",
      "status": "open"
    },
    {
      "op": "create_edge",
      "from": "task_1",
      "to": "question_1",
      "edge_type": "blocked_by"
    }
  ]
}
```

### 8.3 Supported Operations

MVP operations:

```text
create_node
update_node
create_edge
delete_edge
attach_artifact
mark_duplicate
create_work_packet
```

No hard deletion of nodes in MVP. Use archive/supersede.

### 8.4 Validation Rules

Validate:

- Operation shape.
- Node type allowed.
- Edge type allowed.
- Status allowed for node type.
- Temp IDs resolve.
- User/integration/AI has permission.
- Duplicate nodes are detected.
- Required fields exist.
- Confidence threshold is met.
- Risky changes require human review.
- Patch does not create invalid graph cycles for edge types that must be acyclic.

### 8.5 Application

Graph patch application must happen in one database transaction.

On success:

1. Apply node and edge mutations.
2. Write `node_events`.
3. Update `graph_patches.status`.
4. Emit domain events.
5. Broadcast realtime updates.
6. Enqueue follow-up jobs if needed.

---

## 9. AI Pipeline Requirements

### 9.1 AI Provider Abstraction

Create an internal behavior:

```elixir
defmodule WorkGraph.AI.Provider do
  @callback complete(request :: map()) ::
              {:ok, map()} | {:error, term()}
end
```

Do not hard-code one provider into domain modules.

Support:

- Provider name.
- Model name.
- Prompt template version.
- Structured output schema.
- Timeout.
- Retry policy.
- Token/cost metadata.
- Raw response storage where safe.

### 9.2 AI Pipeline Modules

MVP pipelines:

```text
AI.Pipelines.Triage
AI.Pipelines.GraphPatchGenerator
AI.Pipelines.QuestionGenerator
AI.Pipelines.ReadinessScorer
AI.Pipelines.WorkPacketCompiler
AI.Pipelines.Deduplicator
```

### 9.3 Triage Output

```json
{
  "classification": "bug",
  "severity": "medium",
  "recommended_action": "create_task",
  "confidence": 0.82,
  "summary": "OAuth callback crashes when state is invalid."
}
```

### 9.4 Readiness Output

```json
{
  "score": 82,
  "status": "ready_for_agent",
  "reasons": [
    "Narrow scope",
    "Stack trace available",
    "Relevant files identified",
    "Regression test path exists"
  ],
  "risks": [
    "Auth behavior must be confirmed"
  ],
  "recommended_mode": "draft_pr"
}
```

### 9.5 Work Packet Output

Work packet must be available as both Markdown and structured JSON.

Required sections:

```text
title
objective
background
context_artifacts
relevant_files
linked_decisions
constraints
non_goals
success_criteria
verification_steps
autonomy_policy
escalation_rules
suggested_execution_mode
```

---

## 10. Realtime Architecture

### 10.1 Requirements

React clients need realtime updates for:

- New signals.
- Graph changes.
- Question queue changes.
- Task readiness changes.
- Run status changes.
- Work packet recompilation.
- Verification state changes.
- Comments/notes if added later.

### 10.2 Realtime Transport

Use:

- Absinthe GraphQL subscriptions for frontend data updates.
- Phoenix Channels where lower-level custom realtime streams are useful.
- Phoenix PubSub for server-side fanout.
- Phoenix Presence for online users if needed.

Do not use Redis PubSub.
Do not use Postgres LISTEN/NOTIFY for app-level realtime.

### 10.3 Topic Design

Topic helpers:

```elixir
org_topic(org_id)
node_topic(org_id, node_id)
run_topic(org_id, run_id)
question_queue_topic(org_id)
task_queue_topic(org_id)
```

Example topics:

```text
org:ORG_ID
org:ORG_ID:node:NODE_ID
org:ORG_ID:run:RUN_ID
org:ORG_ID:questions
org:ORG_ID:tasks
```

### 10.4 Domain Event Flow

```text
Domain mutation succeeds
  -> emit domain event
  -> publish to Phoenix PubSub
  -> Absinthe subscription receives event
  -> React client updates cache
```

### 10.5 Realtime Events

MVP events:

```text
node_created
node_updated
edge_created
edge_deleted
question_answered
readiness_changed
work_packet_compiled
run_created
run_updated
run_event_added
verification_updated
```

---

## 11. OTP Architecture

### 11.1 Supervision Tree

Suggested supervision tree:

```text
WorkGraph.Application
  ├── WorkGraph.Repo
  ├── Phoenix.PubSub
  ├── WorkGraphWeb.Endpoint
  ├── Oban
  ├── WorkGraph.Realtime.Presence
  ├── WorkGraph.RunRegistry
  ├── WorkGraph.RunSupervisor
  ├── WorkGraph.IntegrationSyncSupervisor
  └── WorkGraph.RateLimitSupervisor
```

### 11.2 Run Processes

For active runs, use supervised processes.

```text
RunSupervisor
  └── RunServer per active run
```

`RunServer` responsibilities:

- Maintain ephemeral run progress.
- Accept progress events.
- Broadcast run updates.
- Persist important run events.
- Handle cancellation.
- Handle timeout.
- Crash safely.

Do not rely on `RunServer` as the only source of truth. Durable run state still belongs in Postgres.

### 11.3 Registries

Use Elixir `Registry` for locating active processes.

Registries:

```text
RunRegistry
IntegrationSyncRegistry
OrgPresenceRegistry if needed
```

### 11.4 Concurrency

Use `Task.Supervisor` for bounded parallel operations:

- Fetching multiple GitHub resources.
- Fetching multiple Sentry events.
- Calling AI pipelines with concurrency limits.
- Compiling multiple work packets.
- Verifying multiple checks.

Use timeouts and cancellation.

### 11.5 Distributed Deployment

MVP should work on one node.

Design should not block later distributed deployment.

For multi-node deployment:

- Use distributed Erlang clustering.
- Use Phoenix PubSub distributed adapter.
- Ensure all nodes use same PubSub pool size.
- Avoid local-only state for durable workflow decisions.
- Keep ephemeral process state recoverable from database.

---

## 12. GraphQL API

### 12.1 GraphQL Stack

Use Absinthe.

API endpoint:

```text
POST /graphql
GET /graphiql or /playground in dev only
WebSocket endpoint for subscriptions
```

### 12.2 Authentication

MVP options:

- Session cookie auth for web app.
- Bearer token for CLI.
- Integration-specific webhook secrets.

GraphQL context should include:

```elixir
%{
  current_user: user,
  organization_id: org_id,
  permissions: permissions
}
```

### 12.3 Authorization

Use authorization middleware for:

- Organization membership.
- Node visibility.
- Integration access.
- Mutations requiring elevated roles.
- Agent-run permissions.
- Decision approval permissions.

### 12.4 Core Types

GraphQL types:

```graphql
type Organization
type User
type Node
type Edge
type Artifact
type ExternalEvent
type GraphPatch
type WorkPacket
type Run
type RunEvent
type QuestionQueueItem
type AgentReadiness
type PageInfo
```

### 12.5 Node Type

```graphql
type Node {
  id: ID!
  organizationId: ID!
  type: NodeType!
  title: String!
  description: String
  status: String!
  riskLevel: String
  readinessScore: Int
  properties: JSON!
  incomingEdges(type: EdgeType): [Edge!]!
  outgoingEdges(type: EdgeType): [Edge!]!
  artifacts(relationship: String): [Artifact!]!
  events: [NodeEvent!]!
  insertedAt: DateTime!
  updatedAt: DateTime!
}
```

### 12.6 Edge Type

```graphql
type Edge {
  id: ID!
  type: EdgeType!
  fromNode: Node!
  toNode: Node!
  properties: JSON!
  confidence: Float
  insertedAt: DateTime!
}
```

### 12.7 Queries

MVP queries:

```graphql
organization(id: ID!): Organization
node(id: ID!): Node
nodes(filter: NodeFilter, first: Int, after: String): NodeConnection
graphAround(nodeId: ID!, depth: Int = 1): GraphProjection
questionQueue(filter: QuestionQueueFilter): [QuestionQueueItem!]!
taskQueue(filter: TaskQueueFilter): [Node!]!
workPacket(taskNodeId: ID!): WorkPacket
run(id: ID!): Run
runs(filter: RunFilter): [Run!]!
externalEvents(filter: ExternalEventFilter): [ExternalEvent!]!
```

### 12.8 Mutations

MVP mutations:

```graphql
createNode(input: CreateNodeInput!): Node!
updateNode(input: UpdateNodeInput!): Node!
archiveNode(id: ID!): Node!

createEdge(input: CreateEdgeInput!): Edge!
deleteEdge(id: ID!): Boolean!

answerQuestion(input: AnswerQuestionInput!): DecisionResult!
dismissQuestion(input: DismissQuestionInput!): Node!

proposeGraphPatch(input: ProposeGraphPatchInput!): GraphPatch!
applyGraphPatch(id: ID!): GraphPatch!
rejectGraphPatch(id: ID!, reason: String): GraphPatch!

compileWorkPacket(taskNodeId: ID!): WorkPacket!
createHandoffRun(input: CreateHandoffRunInput!): Run!

importExternalEvent(input: ImportExternalEventInput!): ExternalEvent!
triggerIntegrationSync(input: TriggerIntegrationSyncInput!): Boolean!
```

### 12.9 Subscriptions

MVP subscriptions:

```graphql
subscription orgEvents(organizationId: ID!): OrgEvent!
subscription nodeUpdated(nodeId: ID!): Node!
subscription questionQueueUpdated(organizationId: ID!): QuestionQueueEvent!
subscription taskQueueUpdated(organizationId: ID!): TaskQueueEvent!
subscription runUpdated(runId: ID!): RunEvent!
subscription graphPatchUpdated(id: ID!): GraphPatch!
```

---

## 13. Integration Architecture

### 13.1 Integration Model

Create table:

```sql
CREATE TABLE integrations (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  provider TEXT NOT NULL,
  status TEXT NOT NULL,
  external_account_id TEXT,
  config JSONB NOT NULL DEFAULT '{}',
  encrypted_credentials BYTEA,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Providers:

```text
github
sentry
linear
jira_future
slack_future
```

### 13.2 GitHub MVP Integration

Support:

- GitHub App installation.
- Repo selection.
- Issue import.
- PR import.
- Commit links.
- Check run / CI status.
- Webhook ingestion.
- Create GitHub issue from work packet.
- Link GitHub PRs to task nodes.

Webhook events:

```text
issues
pull_request
check_run
check_suite
workflow_run
push
```

### 13.3 Sentry MVP Integration

Support:

- Connect Sentry organization/project.
- Import issue.
- Import stack trace as artifact.
- Import event counts.
- Import first seen / last seen.
- Link Sentry issue to task.
- Poll or receive updates for issue resolution / recurrence.

### 13.4 Linear MVP Integration

Support:

- Connect workspace.
- Import issue.
- Create Linear issue from work packet.
- Sync status.
- Comment back with work packet link.
- Link Linear issue to node.

---

## 14. Ingestion Pipeline

### 14.1 Flow

```text
Webhook/API sync
  -> store external_event
  -> dedupe using source + event type + payload hash
  -> normalize
  -> create/update artifacts
  -> create/update signal node
  -> enqueue AI triage
  -> propose graph patch
  -> validate graph patch
  -> apply or require review
  -> broadcast updates
```

### 14.2 Idempotency

Every external event must be idempotent.

Use:

```text
organization_id
source
source_event_type
payload_hash
external_id where available
```

### 14.3 Replay

Admin/dev tools should allow replaying external events.

Use case:

- AI prompt improved.
- Normalizer bug fixed.
- Integration parser changed.
- Need to regenerate graph patch.

---

## 15. Work Packet Compiler

### 15.1 Input

Given a task node, collect:

- Task title and description.
- Incoming `generated_from` edges.
- Related signal nodes.
- Open/answered questions.
- Decision nodes.
- Check nodes.
- Artifacts.
- Evidence.
- Constraints from properties.
- Autonomy policy.
- Relevant recent external events.

### 15.2 Output JSON

```json
{
  "title": "Fix OAuth callback crash",
  "objective": "Handle invalid OAuth state without throwing a 500.",
  "background": "...",
  "context_artifacts": [],
  "relevant_files": [],
  "linked_decisions": [],
  "constraints": [],
  "non_goals": [],
  "success_criteria": [],
  "verification_steps": [],
  "autonomy_policy": {},
  "escalation_rules": [],
  "suggested_execution_mode": "draft_pr"
}
```

### 15.3 Output Markdown

Must be stable, readable, and useful to coding agents.

Markdown sections:

```markdown
# Task

## Objective

## Background

## Context

## Relevant Files

## Decisions

## Constraints

## Non-Goals

## Success Criteria

## Verification Steps

## Autonomy Policy

## Escalation Rules
```

### 15.4 Versioning

Each compiled work packet gets a version.

Recompile when:

- Task changes.
- Question is answered.
- Decision changes.
- Artifact is added.
- Success criteria change.
- Autonomy policy changes.
- Relevant evidence changes.

---

## 16. Agent Readiness

### 16.1 Purpose

Agent readiness determines whether a task is safe and clear enough to hand to an AI coding agent.

### 16.2 Inputs

Use deterministic and AI-derived factors.

Deterministic factors:

```text
has_objective
has_context_artifacts
has_success_criteria
has_open_blocking_questions
has_linked_signal
has_verification_path
has_risky_area
has_autonomy_policy
```

AI-derived factors:

```text
ambiguity_level
scope_clarity
risk_assessment
expected_complexity
suggested_execution_mode
```

### 16.3 Output

```json
{
  "score": 82,
  "status": "ready_for_agent",
  "reasons": [],
  "risks": [],
  "blocking_question_ids": [],
  "recommended_mode": "draft_pr"
}
```

### 16.4 Status Mapping

```text
0-30: human_only
31-50: needs_context
51-70: needs_human_answer or needs_review
71-85: ready_for_agent_investigate_or_plan
86-100: ready_for_agent_execution
```

---

## 17. Question Queue

### 17.1 Question Node Requirements

A question node should include:

```text
question text
why it matters
recommended answer
available options
risk of proceeding without answer
blocked node IDs
source artifacts
confidence
```

### 17.2 Answering a Question

When answered:

1. Create decision node.
2. Link decision to question.
3. Mark question answered.
4. Link decision to affected task nodes.
5. Recalculate readiness.
6. Recompile work packets.
7. Broadcast updates.

### 17.3 Dismissing a Question

Dismissing requires reason.

Dismissed questions should not be deleted.

---

## 18. Verification System

### 18.1 Checks

Check nodes define what must be true.

Examples:

```text
Regression test added
CI passes
PR merged
Sentry issue quiet for 24h
Human reviewer approved
No new error events after deploy
```

### 18.2 Evidence

Evidence nodes/artifacts prove or disprove checks.

Examples:

```text
GitHub Actions run passed
PR #914 merged
Sentry issue resolved
Human approval
```

### 18.3 Verification Logic

Task can become `verified` only when:

- Required checks pass; or
- Required checks are waived by authorized user; and
- No blocking questions remain; and
- No blocking dependencies remain; and
- Review policy is satisfied.

### 18.4 Monitoring State

Some tasks enter `monitoring` after merge/deploy.

Example:

```text
Task is implemented, but Sentry issue must remain quiet for 24h before verified.
```

---

## 19. Local CLI / Task Bundle Requirements

The backend should expose enough API to support a CLI later.

Command:

```bash
taskgraph pull TASK_ID
```

Creates:

```text
.taskgraph/TASK_ID/
  task.md
  context.md
  decisions.md
  success_criteria.md
  artifacts.json
  policy.json
```

Command:

```bash
taskgraph submit TASK_ID
```

Submits:

```text
branch
commits
PR URL
test output
new questions
notes
```

Backend requirements:

- API token auth.
- Fetch current work packet.
- Attach local output artifacts.
- Create run event.
- Link PR/branch to task.
- Allow user/agent to raise new questions.

---

## 20. Security Requirements

### 20.1 Secrets

Integration credentials must be encrypted at rest.

Do not expose raw credentials to GraphQL.

### 20.2 Permissions

Actions requiring authorization:

```text
connect integration
view repo artifacts
create graph patch
apply graph patch
answer question
approve decision
create handoff run
waive check
verify task
```

### 20.3 Webhook Security

Verify signatures for providers that support them.

Reject unsigned or invalid webhooks.

### 20.4 AI Data Controls

For MVP:

- Store prompt inputs and outputs only when allowed by organization settings.
- Redact secrets from logs and AI prompts.
- Do not include environment variables or secret files in AI context.
- Allow org-level setting to disable sending source code snippets to AI providers.

---

## 21. Observability

Backend should log:

- Webhook receipt.
- External event processing.
- Graph patch generation.
- Graph patch validation failures.
- AI calls.
- Job retries.
- Integration API failures.
- Work packet compilation.
- Realtime broadcast failures.
- GraphQL resolver errors.

Metrics to track:

```text
external_events_received
external_events_processed
graph_patches_generated
graph_patches_applied
graph_patch_validation_failures
questions_created
questions_answered
tasks_ready_for_agent
work_packets_compiled
runs_created
tasks_verified
ai_call_latency
ai_call_cost
integration_sync_latency
```

---

## 22. Testing Requirements

### 22.1 Unit Tests

Test:

- Node changesets.
- Edge changesets.
- Graph patch validation.
- Graph patch application.
- Readiness scoring deterministic component.
- Work packet compilation.
- Question answer flow.
- Verification logic.
- Permission checks.

### 22.2 Integration Tests

Test:

- GitHub webhook ingestion.
- Sentry webhook ingestion.
- Linear issue creation.
- GraphQL mutations.
- GraphQL subscriptions.
- Oban job processing.
- Realtime PubSub broadcast.

### 22.3 Property Tests

Good candidates:

- Graph patch application is transactional.
- Invalid graph patches never partially apply.
- Acyclic edge types remain acyclic.
- Readiness status is consistent with blocking questions.
- Verification cannot pass with failed required checks.

### 22.4 Contract Tests

For AI pipelines:

- Given fixed input, output matches expected JSON schema.
- Invalid AI output is rejected.
- Missing required fields cause validation failure.
- Unknown node/edge types are rejected.

---

## 23. MVP Implementation Milestones

### Milestone 1: Project Foundation

Deliverables:

- Phoenix app without LiveView.
- Absinthe GraphQL setup.
- React-compatible CORS/auth setup.
- Postgres repo.
- Basic users/orgs/memberships.
- Basic GraphQL auth context.
- Basic PubSub wiring.

Acceptance criteria:

- React client can authenticate and call GraphQL.
- GraphQL context includes current user and org.
- Basic subscription works over WebSocket.

---

### Milestone 2: Core Work Graph

Deliverables:

- `nodes` table.
- `edges` table.
- `node_events` audit table.
- Graph context module.
- Create/update/archive node mutations.
- Create/delete edge mutations.
- Query node and graph neighborhood.

Acceptance criteria:

- User can create task, question, check, artifact nodes.
- User can link nodes with typed edges.
- Invalid edge/node types are rejected.
- Graph changes produce audit events.
- Graph changes broadcast realtime updates.

---

### Milestone 3: External Event Ingestion

Deliverables:

- `external_events` table.
- Generic ingestion pipeline.
- Manual external event import mutation.
- Processing job.
- Signal node creation.

Acceptance criteria:

- Pasted mock Sentry/GitHub payload becomes external event.
- External event creates or updates signal node.
- Duplicate event is ignored.
- Event processing is replayable.

---

### Milestone 4: Graph Patch System

Deliverables:

- `graph_patches` table.
- GraphPatch schema.
- Validation module.
- Apply/reject mutations.
- Transactional patch application.
- Audit trail integration.

Acceptance criteria:

- Valid patch creates nodes/edges.
- Invalid patch fails with useful errors.
- Failed patch does not partially apply.
- Applied patch emits realtime updates.

---

### Milestone 5: AI Pipeline Skeleton

Deliverables:

- AI provider behavior.
- Mock provider for tests/dev.
- Triage pipeline.
- GraphPatchGenerator pipeline.
- ReadinessScorer pipeline.
- WorkPacketCompiler pipeline.
- Structured output validation.

Acceptance criteria:

- Given a mock issue payload, AI pipeline proposes task/question/check graph patch.
- Invalid AI output is rejected.
- Generated graph patch can be reviewed and applied.

---

### Milestone 6: Question Queue

Deliverables:

- Question queue query.
- Answer question mutation.
- Decision node creation.
- Readiness recalculation trigger.
- Realtime question queue updates.

Acceptance criteria:

- Open questions appear in queue.
- Answering a question creates decision node.
- Answering a question unblocks linked task.
- Frontend receives subscription update.

---

### Milestone 7: Work Packet Compilation

Deliverables:

- `work_packets` table.
- Compile work packet mutation.
- Markdown output.
- JSON output.
- Versioning.
- Recompile on relevant graph changes.

Acceptance criteria:

- Task with linked signal/question/decision/check compiles into useful packet.
- Packet version increments when relevant context changes.
- Current packet is queryable over GraphQL.

---

### Milestone 8: GitHub MVP Integration

Deliverables:

- GitHub integration config.
- Webhook endpoint.
- Signature verification.
- Issue/PR/check-run ingestion.
- Artifact creation.
- Create GitHub issue from work packet.

Acceptance criteria:

- GitHub issue webhook creates external event and artifact.
- GitHub PR webhook links PR to task when references match.
- GitHub check-run updates check/evidence.
- User can create GitHub issue from task packet.

---

### Milestone 9: Sentry MVP Integration

Deliverables:

- Sentry integration config.
- Issue import.
- Stack trace artifact creation.
- Issue status sync.
- Sentry issue to signal conversion.

Acceptance criteria:

- Sentry issue creates signal node.
- Stack trace is attached as artifact.
- AI pipeline generates task/question/check proposal.
- Sentry resolution/recurrence can update evidence.

---

### Milestone 10: Runs and Handoff

Deliverables:

- `runs` table.
- `run_events` table.
- Create handoff run mutation.
- RunServer process.
- Run PubSub updates.
- Markdown copy / external issue handoff.

Acceptance criteria:

- User can create handoff run for a task.
- Run status updates are persisted and broadcast.
- Run can attach output artifacts.
- Run can raise new question.

---

### Milestone 11: Verification

Deliverables:

- Check evaluation module.
- Evidence linking.
- Verification status calculation.
- Monitoring state.
- Waive check mutation.

Acceptance criteria:

- Task cannot be verified while required check is failed/open.
- Passing CI evidence can satisfy check.
- Merged PR evidence can satisfy check.
- Human can waive check with permission and reason.
- Verified task broadcasts update.

---

## 24. GraphQL Example Operations

### 24.1 Create Node

```graphql
mutation CreateTask($input: CreateNodeInput!) {
  createNode(input: $input) {
    id
    type
    title
    status
  }
}
```

### 24.2 Answer Question

```graphql
mutation AnswerQuestion($input: AnswerQuestionInput!) {
  answerQuestion(input: $input) {
    question {
      id
      status
    }
    decision {
      id
      title
    }
    affectedTasks {
      id
      status
      readinessScore
    }
  }
}
```

### 24.3 Compile Work Packet

```graphql
mutation CompileWorkPacket($taskNodeId: ID!) {
  compileWorkPacket(taskNodeId: $taskNodeId) {
    id
    version
    markdown
    json
    status
  }
}
```

### 24.4 Subscribe to Run Updates

```graphql
subscription RunUpdated($runId: ID!) {
  runUpdated(runId: $runId) {
    id
    eventType
    payload
    insertedAt
  }
}
```

---

## 25. Backend Acceptance Criteria for MVP

The backend MVP is complete when:

1. A user can create an organization and authenticate.
2. A user can create and query graph nodes and edges.
3. A user can import a mock or real Sentry/GitHub event.
4. The system stores the raw event durably.
5. The system creates a signal node from the event.
6. The AI pipeline proposes a graph patch.
7. The graph patch can create task, question, and check nodes.
8. A human can answer a generated question.
9. Answering a question creates a decision node.
10. A task can be scored for agent readiness.
11. A task can compile into a Markdown and JSON work packet.
12. A work packet can be used to create a GitHub or Linear issue.
13. GitHub PR/check events can attach evidence.
14. Verification logic can mark a task as verified.
15. React clients receive realtime updates over GraphQL subscriptions.
16. No Redis is required.
17. No LiveView is used.
18. Realtime fanout uses Phoenix PubSub/Channels/Absinthe subscriptions.
19. Ephemeral run state uses OTP processes.
20. Durable state remains recoverable from Postgres.

---

## 26. Technical Design Constraints

### 26.1 Required Stack

```text
Elixir
Phoenix
Absinthe GraphQL
Postgres
React frontend
Phoenix PubSub
Phoenix Channels
OTP supervisors/processes
```

### 26.2 Forbidden for MVP

```text
LiveView
Redis
Postgres LISTEN/NOTIFY for app realtime
Postgres advisory locks as primary distributed lock system
Kafka
RabbitMQ
Neo4j
Microservice split
Custom coding agent runtime
```

### 26.3 Allowed but Optional

```text
Oban for durable jobs
pgvector for future retrieval
OpenTelemetry
S3-compatible object storage
GitHub App
Sentry OAuth/API tokens
Linear OAuth/API tokens
```

---

## 27. Codex Implementation Guidance

When implementing, proceed in this order:

1. Generate Phoenix project configured for API usage, no LiveView.
2. Add Absinthe GraphQL.
3. Add Ecto/Postgres.
4. Add authentication and organization membership.
5. Implement graph schema and context.
6. Implement GraphQL node/edge CRUD.
7. Implement PubSub publishing from graph mutations.
8. Implement GraphQL subscriptions.
9. Implement external event ingestion.
10. Implement graph patch schema and validator.
11. Implement mock AI provider.
12. Implement AI pipeline interfaces.
13. Implement question queue and answer flow.
14. Implement work packet compiler.
15. Implement run/handoff model.
16. Implement verification model.
17. Add GitHub integration.
18. Add Sentry integration.
19. Add Linear integration.
20. Harden tests, permissions, and audit trails.

Prefer small, testable modules.

Do not let AI pipeline code write directly to database tables except through validated domain services.

Do not place business logic in GraphQL resolvers.

Resolvers should call context modules.

---

## 28. Suggested Initial Mix Dependencies

Exact versions should be checked during implementation.

Core:

```elixir
:phoenix
:ecto_sql
:postgrex
:absinthe
:absinthe_plug
:absinthe_phoenix
:phoenix_pubsub
:jason
:oban
:tesla or :req
:telemetry
:telemetry_metrics
:telemetry_poller
```

Useful:

```elixir
:ecto_enum or custom enum validation
:nimble_options
:nimble_parsec if needed
:hammer or custom rate limiting
:swoosh if email needed
:cloak_ecto for encrypted credentials
```

Testing:

```elixir
:ex_machina
:mox
:bypass
:stream_data
```

---

## 29. Open Product Questions

Resolve before or during implementation:

1. Will users authenticate with email/password, OAuth, or magic links?
2. Should every organization have exactly one graph, or multiple projects/graphs?
3. Should graph nodes belong to projects initially?
4. Should work packets be immutable once used for a run?
5. Should AI-generated graph patches auto-apply below a confidence/risk threshold?
6. How much source code can be sent to external AI providers?
7. Should Sentry/GitHub integrations be required for MVP, or can manual import prove the loop?
8. Should Linear be first-class in MVP or phase two?
9. Should CLI support be part of MVP or immediately post-MVP?
10. Should GraphQL subscriptions be the only realtime API, or should some run streams use raw Phoenix Channels?

---

## 30. Recommended MVP Cut

The smallest valuable backend should include:

```text
Accounts/orgs
Graph nodes/edges
External event ingestion
Manual import
Graph patch proposal/application
Mock AI provider
Question queue
Decision creation
Readiness scoring
Work packet compilation
GraphQL subscriptions
Runs/handoff records
Verification basics
```

Then add real GitHub and Sentry integrations.

This avoids blocking the entire product on OAuth and external API complexity before validating the core loop.

---

## 31. Final Backend Definition

The backend is:

> A Phoenix/Absinthe API backed by Postgres that stores a typed work graph, ingests external engineering signals, applies validated AI-generated graph patches, compiles agent-ready work packets, coordinates realtime updates through OTP/Phoenix PubSub, and verifies completion through durable evidence from GitHub, Sentry, CI, and human review.

Its most important invariant:

> The graph is the source of truth. AI proposes changes. Humans and validated domain logic decide what becomes true.