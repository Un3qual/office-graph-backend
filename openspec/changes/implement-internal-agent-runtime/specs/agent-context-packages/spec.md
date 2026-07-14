## ADDED Requirements

### Requirement: Context Packages Are Immutable Authorized References
Office Graph SHALL assemble immutable execution context packages from authorized
projection references rather than direct graph-table traversal.

#### Scenario: Context package is created
- **WHEN** an authorized execution starts
- **THEN** the package MUST record selected item, run, included typed references,
  relevant external references/checks/evidence, inclusion rationale, authority
  snapshot, and operation without copying graph truth

#### Scenario: Context is restricted
- **WHEN** relevant context is outside scope, sensitivity, credential, or
  autonomy policy
- **THEN** the package MUST record omitted, redacted, restricted, or
  expansion-required posture with a safe rationale and MUST NOT include the
  restricted value

### Requirement: Context Expansion Is Explicit
Office Graph SHALL require a durable context-expansion request before an agent
can receive context outside its current package.

#### Scenario: Agent requests broader context
- **WHEN** an execution requests additional scope, resource, sensitivity, or
  integration context
- **THEN** the runtime MUST pause the matching step and create a request naming
  target, reason, capability, access mode, and expected duration

#### Scenario: Expansion is approved
- **WHEN** an authorized resolver approves bounded additional context
- **THEN** the runtime MUST create a new context package version linked to the
  decision rather than mutate the prior package
