## ADDED Requirements

### Requirement: MVP Conversations Are Run Aware And Persisted
Office Graph SHALL persist conversations and messages attached to one selected
graph item and work run for the first agent runtime surface.

#### Scenario: Human starts run conversation
- **WHEN** an authorized operator opens the focused conversation for a selected
  run and graph item
- **THEN** Office Graph MUST create or read a conversation with scope,
  visibility, participants, purpose, and operation provenance

#### Scenario: Agent adds a message
- **WHEN** an execution contributes a validated conversation message
- **THEN** the message MUST retain agent principal, execution, context package,
  operation, visibility, and timestamp

#### Scenario: Message proposes product change
- **WHEN** a human or agent message requests durable graph/domain work
- **THEN** the change MUST use an explicit proposal or domain command linked back
  to the message and MUST NOT occur as a hidden chat side effect

### Requirement: Conversation Reads Are Authorization Filtered
Office Graph SHALL authorize conversation, message, selected item, and related
context independently.

#### Scenario: Actor can read conversation but not referenced context
- **WHEN** a message references context outside the actor's current visibility
- **THEN** the projection MUST redact or omit that context without granting
  access through conversation membership
