## ADDED Requirements

### Requirement: Agent Verification Material Starts As A Candidate
Office Graph SHALL store agent-produced verification material as an evidence
candidate or observation until the owning verification workflow accepts it.
The selected artifact type SHALL be unique for a stable execution and step.

#### Scenario: Agent produces check material
- **WHEN** a validated agent output claims a check passed, failed, or is waived
- **THEN** AgentRuntime MUST create a typed candidate or observation with
  execution/context provenance and MUST NOT create an accepted evidence item or
  verification result directly

#### Scenario: Candidate is accepted
- **WHEN** an authorized verification command accepts agent-produced evidence
- **THEN** the resulting evidence and decision MUST retain links to the agent
  execution, context package, operation, and accepting actor

#### Scenario: Agent attempt is replayed
- **WHEN** the same execution step is retried after candidate or observation
  creation
- **THEN** Office Graph MUST return the existing artifact of the selected type
  without duplicate candidate, observation, evidence, or verification effects
