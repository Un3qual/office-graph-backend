## ADDED Requirements

### Requirement: MVP Conversations Are Run Aware And Persisted
Office Graph SHALL persist conversations and messages attached to one selected
graph item and work run for the first agent runtime surface.

#### Scenario: Human starts run conversation
- **WHEN** an authorized operator opens the focused conversation for a selected
  run and graph item
- **THEN** Office Graph MUST create or read a conversation with scope,
  visibility, participants, purpose, and operation provenance

#### Scenario: Conversation command is replayed

- **WHEN** the same authorized command input is replayed for a selected run and
  graph item
- **THEN** Office Graph MUST return the existing conversation or message and
  MUST reject reuse of that operation identity with different input

#### Scenario: Conversation scope is not part of the run

- **WHEN** an operator tries to start a conversation for a graph item outside
  the selected run's packet-source contract
- **THEN** Office Graph MUST reject the command before creating a conversation

#### Scenario: Human adds a message

- **WHEN** an actor with conversation-write authority contributes to the active
  run conversation
- **THEN** the message MUST retain that human principal, operation, visibility,
  body fingerprint, and explicit contribution linkage without performing a
  hidden product mutation

#### Scenario: Agent adds a message
- **WHEN** an execution contributes a validated conversation message
- **THEN** the message MUST retain agent principal, execution, context package,
  operation, visibility, and timestamp

#### Scenario: Message proposes product change
- **WHEN** a human or agent message requests durable graph/domain work
- **THEN** the change MUST use an explicit proposal or domain command linked back
  to the message and MUST NOT occur as a hidden chat side effect

#### Scenario: Message linkage crosses scope

- **WHEN** a human message names a proposal or domain operation outside the
  actor's organization and workspace
- **THEN** Office Graph MUST reject the message without exposing or attaching
  the foreign record

### Requirement: Conversation Reads Are Authorization Filtered
Office Graph SHALL authorize conversation, message, selected item, and related
context independently.

#### Scenario: Actor can read conversation but not referenced context
- **WHEN** a message references context outside the actor's current visibility
- **THEN** the projection MUST redact or omit that context without granting
  access through conversation membership

#### Scenario: Focused conversation projection is read

- **WHEN** an authorized operator reads a selected run conversation
- **THEN** the bounded projection MUST include safe human and agent message
  provenance, current execution summaries, and exact approval/context-expansion
  request metadata needed by the focused operator surface
