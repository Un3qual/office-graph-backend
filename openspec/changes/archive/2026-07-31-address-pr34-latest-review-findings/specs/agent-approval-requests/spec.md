## ADDED Requirements

### Requirement: One-capability approval gates fail closed

Office Graph SHALL accept an approval-required adapter manifest only when the step declares exactly one capability represented by its durable approval request.

#### Scenario: Approval-required manifest declares one capability

- **WHEN** an otherwise valid adapter manifest requires approval and declares exactly one capability authorized by the snapshot
- **THEN** the worker MAY create one replay-safe approval request representing that capability

#### Scenario: Approval-required manifest declares multiple capabilities

- **WHEN** an adapter manifest requires approval and declares more than one capability
- **THEN** manifest preflight MUST fail closed before creating an approval request or dispatching the adapter

#### Scenario: Non-approval adapter declares multiple capabilities

- **WHEN** an otherwise valid adapter manifest does not require approval and declares multiple capabilities authorized by the snapshot
- **THEN** the adapter contract MAY continue to validate the complete capability set without creating an approval request
