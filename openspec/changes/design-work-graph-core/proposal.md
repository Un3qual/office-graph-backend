## Why

Office Graph needs a concrete core work-graph model before persistence,
agent-runtime, API, and UI projection designs can be coherent. The foundation
and enterprise-governance changes define the product frame, tenancy posture,
and authorization guardrails; this change turns those decisions into the first
department-neutral graph semantics for work containers, graph items,
relationships, projections, and addressable conversations.

## What Changes

- Define the product meaning of core graph items such as signals, tasks,
  questions, decisions, requirements, checks, evidence, artifacts, runs, work
  packets, conversations, and external references.
- Define initiative/project and workstream behavior inside the work graph,
  including how teams, components, repositories, departments, services, and
  external systems attach to work without becoming projects by default.
- Define typed graph relationships with direction, lifecycle, validation,
  provenance, traversal, and authorization expectations.
- Define graph projections as filtered views over scoped graph data rather
  than access-granting containers or tenants.
- Define how domain-specific records attach to the graph without forcing
  software-specific, marketing-specific, finance-specific, or design-specific
  concepts into the shared ontology.
- Define how addressable graph items support node-scoped conversation and
  context assembly while deferring full agent runtime execution design.
- Establish boundaries between the core graph model and follow-on changes for
  persistence schema, revision/audit/soft-delete, proposed graph changes, work
  packets/readiness, runs/verification, integrations, and APIs.

## Capabilities

### New Capabilities

- `work-containers`: Defines workspace-visible initiatives/projects,
  workstreams, and related team/component/resource attachment semantics.
- `graph-items`: Defines addressable department-neutral graph item categories,
  common lifecycle expectations, ownership, provenance, and status vocabulary.
- `graph-relationships`: Defines typed edges, allowed relationship semantics,
  traversal expectations, validation constraints, and access-control
  implications.
- `graph-projections`: Defines filtered graph views such as inboxes, question
  queues, focused node neighborhoods, dependency views, and evidence chains.
- `domain-attachments`: Defines how domain-specific records and external
  references attach to the shared graph without redefining the core ontology.
- `node-conversations`: Defines how selected graph items host scoped human or
  agent conversations and what graph context those conversations may request.

### Modified Capabilities

- None. No durable specs exist yet under `openspec/specs/`; this change builds
  on active foundation and enterprise-governance changes without modifying an
  accepted capability spec.

## Impact

- Affects OpenSpec planning artifacts for the Office Graph product model.
- Provides source requirements for later Phoenix, Ash, Postgres, GraphQL, JSON
  API, React, and realtime projection design.
- Feeds follow-on changes for persistence, revision/audit/soft-delete, code
  organization, agent runtime, ingestion/integrations, proposed graph changes,
  work packets/readiness, runs/verification, and API/UI projections.
- Does not implement application code, database migrations, API endpoints,
  frontend screens, or agent execution behavior.
