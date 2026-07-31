## MODIFIED Requirements

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

#### Scenario: Active work competes with terminal history

- **WHEN** more terminal executions or resolved gate requests exist than the
  focused operator history bound can return
- **THEN** both the command projection and generated Relay read MUST retain
  nonterminal executions and pending approval/context-expansion requests ahead
  of terminal or resolved history while keeping each returned collection within
  the bound
