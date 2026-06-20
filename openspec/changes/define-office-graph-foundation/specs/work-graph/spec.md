## ADDED Requirements

This foundation capability is framing. Canonical graph item and relationship
requirements are owned by `design-work-graph-core`; proposed mutation safety
semantics are owned by `design-proposed-graph-changes` when created.

### Requirement: Department-Neutral Work Graph

Office Graph SHALL model work as a typed, department-neutral graph of
addressable items and relationships.

#### Scenario: Core node types are defined

- **WHEN** the core graph taxonomy is designed
- **THEN** it must include shared concepts such as signals, tasks, questions,
  decisions, requirements, checks, evidence, artifacts, runs, work packets,
  conversations, and external references without making software-specific
  concepts mandatory for all departments

#### Scenario: Department-specific data is added

- **WHEN** domain-specific objects such as pull requests, design annotations,
  campaign assets, social posts, finance exceptions, or documents are modeled
- **THEN** they must attach to the shared graph through typed records,
  references, and edges rather than redefining the core graph for one
  department

### Requirement: Addressable Graph Items

Every meaningful graph item SHALL be addressable enough to support scoped
conversation, review, provenance, and future automation.

#### Scenario: User selects a graph item

- **WHEN** a user selects a task, requirement, plan section, review finding,
  check, evidence item, run, artifact, or decision
- **THEN** the system must be able to start or continue a conversation scoped
  to that item and its authorized context

### Requirement: Typed Edges With Explicit Semantics

Graph relationships SHALL use typed edges with explicit semantics and
validation rules.

#### Scenario: Edge type is introduced

- **WHEN** an edge type is added
- **THEN** its direction, meaning, allowed source and target types, lifecycle,
  authorization implications, and cycle rules must be defined

#### Scenario: Graph traversal crosses a boundary

- **WHEN** a graph traversal reaches an item outside the actor's permitted
  scope
- **THEN** the edge must not grant access by itself; the response must hide the
  item, redact it, summarize it, or expose a placeholder according to policy

### Requirement: Proposed Graph Changes

Agents and AI pipelines SHALL propose structured graph changes instead of
writing directly to truth tables.

#### Scenario: Agent suggests graph mutations

- **WHEN** an agent, model, integration, or generated UI proposes new work,
  updates, links, decisions, checks, evidence, or packet changes
- **THEN** the proposal must pass through validation, authorization, and
  domain actions before durable graph state changes

#### Scenario: Product language is chosen

- **WHEN** the mutation safety pattern is described in product or planning
  documents
- **THEN** it must use language such as proposed graph change rather than
  legacy patch terminology as the product term

### Requirement: Work Packets As Versioned Execution Packages

Office Graph SHALL represent delegated work through versioned work packets.

#### Scenario: Work is prepared for execution

- **WHEN** a human or agent is given work
- **THEN** the work packet must include objective, scoped context,
  requirements, decisions, constraints, artifacts, autonomy policy, success
  criteria, verification steps, and escalation rules

#### Scenario: Packet context changes

- **WHEN** linked questions, decisions, artifacts, checks, requirements, or
  autonomy policy change
- **THEN** affected work packets must be invalidated, superseded, or
  recompiled with traceable version history

### Requirement: Questions, Decisions, And Micro-Approvals

Office Graph SHALL convert ambiguity into explicit questions, decisions, and
approval records.

#### Scenario: A blocker is detected

- **WHEN** a signal, task, review, or run lacks information needed for safe
  delegation or verification
- **THEN** the system must represent the ambiguity as a question linked to the
  affected graph items

#### Scenario: User gives quick feedback

- **WHEN** a user approves, rejects, edits, or answers a small proposed item
- **THEN** the system must record the decision, actor, affected graph items,
  rationale when available, and feedback signal for future suggestions
