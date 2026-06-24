# node-conversations Specification

## Purpose

Define node-scoped conversation behavior, authorized context assembly,
embedded-agent boundaries, provenance, and graph-action routing for
addressable Office Graph items.

## Requirements

### Requirement: Conversations Attach To Addressable Graph Items

Office Graph SHALL allow conversations to attach to addressable graph items
rather than only to top-level projects.

#### Scenario: User starts node conversation

- **WHEN** a user selects a task, requirement, question, decision, check,
  evidence item, artifact, run, work packet, review finding, document section,
  plan section, external reference, or other addressable graph item
- **THEN** the system MUST be able to start or continue a conversation scoped
  to that selected item

#### Scenario: Multiple conversations exist

- **WHEN** separate groups, agents, or workflows need distinct discussions
  about the same graph item
- **THEN** the graph item MUST be able to host multiple conversations with
  separate participants, purpose, visibility, and provenance

### Requirement: Conversation Context Assembly

Office Graph SHALL assemble node conversation context from authorized graph
neighbors and related typed records.

#### Scenario: Conversation context is assembled

- **WHEN** a human or embedded agent opens a conversation on a selected graph
  item
- **THEN** the context MAY include the selected item, authorized neighboring
  nodes, relevant requirements, decisions, checks, evidence, artifacts,
  external references, work packets, and recent runs according to projection,
  authorization, classification, and AI data-control policy

#### Scenario: Context crosses boundary

- **WHEN** useful conversation context exists outside the actor's permitted
  scope or classification boundary
- **THEN** the conversation context MUST hide it, redact it, summarize it,
  expose a restricted placeholder, or request approved context expansion
  according to policy

### Requirement: Embedded Agent Conversation Boundaries

Office Graph SHALL keep embedded agent conversations inside the same graph,
authorization, and mutation-safety boundaries as other agent activity.

#### Scenario: Embedded agent proposes work

- **WHEN** an embedded agent drafts an answer, suggests a task, identifies a
  missing requirement, proposes an edge, recommends a check, or summarizes
  evidence from a node conversation
- **THEN** the output MUST be represented as a draft, suggestion, or change
  proposal until validated domain actions accept it

#### Scenario: Embedded agent needs tools

- **WHEN** an embedded agent conversation needs tool use, external writes,
  credential access, broad context, or run execution
- **THEN** the request MUST be governed by the later agent-runtime authority
  model and MUST NOT be implied by conversation membership alone

### Requirement: Conversation Provenance

Office Graph SHALL preserve provenance for human and agent contributions to
node-scoped conversations.

#### Scenario: Message is added

- **WHEN** a human, agent, integration, system job, or imported provider thread
  adds a conversation message
- **THEN** the message MUST retain authoring principal or source when
  available, related graph item, conversation, timestamp, provenance, and
  visibility context sufficient for later audit and revision designs

#### Scenario: Conversation affects graph state

- **WHEN** a conversation answer or suggestion affects a question, decision,
  task, requirement, check, evidence item, work packet, run, or relationship
- **THEN** the affected change proposal or accepted domain action MUST preserve
  a link back to the conversation contribution that caused or justified it

### Requirement: Conversation Surfaces Prefer Graph Actions

Office Graph SHALL route durable conversation-driven changes through explicit
graph or domain actions rather than hidden chat side effects.

#### Scenario: User asks conversation to change work

- **WHEN** a user asks a node conversation to add a task, answer a question,
  update a requirement, create a check, attach evidence, or link an external
  artifact
- **THEN** the system MUST represent the intended durable change as an
  explicit domain action or change proposal with validation and
  authorization

#### Scenario: Conversation contains informal discussion

- **WHEN** a conversation includes informal discussion, hypotheses, or notes
  that have not been accepted as graph state
- **THEN** Office Graph MUST NOT treat the informal text as authoritative
  requirements, decisions, checks, evidence, or task state
