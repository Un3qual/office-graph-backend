# Define Office Graph Foundation

## Why

Office Graph needs a durable product and backend foundation before application
code is generated. The product target is entire companies, not only software
engineering departments, and the backend is expected to become large. Without a
clear foundation, early implementation risks overfitting to software workflows,
storing core data in vague JSON blobs, bolting on enterprise permissions later,
or building an agent runner without a differentiated work graph.

The existing ChatGPT reference thread and generated PRD are useful research
inputs, but they are not final requirements. This change promotes only the
current locked decisions into formal OpenSpec artifacts.

## What Changes

- Establish Office Graph as a company-wide, agent-native work graph for
  human-agent planning, execution, review, and verification.
- Treat the software review/fix/verification loop as the first deep proving
  workflow without making the product engineering-only.
- Record the integrate-first, native-workflow-later strategy: Office Graph
  should connect to existing tools while building graph-native experiences that
  are better and harder for any one integrated vendor to absorb as a feature.
- Lock the backend posture: Elixir, Phoenix, Ash, Postgres, React frontend,
  GraphQL and JSON API, no LiveView, modular monolith, Boundary, and DDD-style
  bounded contexts.
- Define the foundation for graph items, proposed graph changes, work packets,
  internal agents, runs, authorization, verification evidence, typed
  persistence, revision history, audit, and soft deletion.
- Record architecture constraints that keep future extraction possible for
  authentication/identity, authorization, agent runtime, integrations, and
  revision/audit primitives.

## Capabilities

- `foundation`
- `work-graph`
- `authorization`
- `verification`
- `persistence`
- `backend-architecture`

## Non-Goals

- No Phoenix, Ash, React, migration, or API implementation in this change.
- No final PRD approval.
- No Linear planning requirement.
- No full workflow builder, full graph editor, marketplace, or IDE replacement.
- No complete provider integration design; integrations get separate changes.
- No final schema for every table; this change defines design rules and
  required properties for future schema work.

## Impact

This change affects OpenSpec planning artifacts only. It creates the foundation
that later implementation changes must follow, especially the first backend
scaffolding, graph core, persistence, authorization, agent runtime, and
integration changes.
