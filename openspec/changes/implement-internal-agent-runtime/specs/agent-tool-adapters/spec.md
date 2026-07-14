## ADDED Requirements

### Requirement: Model And Tool Adapters Have Typed Manifests
Office Graph SHALL register model and tool adapters with typed input/output,
capability, credential, sensitivity, external-write, timeout, budget, and output
classification contracts.

#### Scenario: Adapter request is valid
- **WHEN** an execution requests a declared adapter with valid typed input and
  effective authority
- **THEN** the runtime MUST create a durable request with operation, context,
  adapter version, limits, and idempotency identity

#### Scenario: Adapter input or authority is invalid
- **WHEN** input fails the manifest or effective authority lacks a required
  capability, credential, scope, or approval
- **THEN** the runtime MUST reject or pause the step before adapter execution

### Requirement: Adapter Outputs Are Untrusted And Classified
Office Graph SHALL validate adapter output and classify it before any owning
domain consumes it.

#### Scenario: Model returns structured suggestion
- **WHEN** a model returns a finding, relationship suggestion, proposal input,
  or verification material
- **THEN** the runtime MUST validate it and classify it as a proposal, finding,
  evidence candidate, message, observation, or error before routing

#### Scenario: Adapter returns malformed output
- **WHEN** output does not match the declared schema or safe size limits
- **THEN** the step MUST fail with a safe classified error and MUST NOT create
  graph, proposal, evidence, or external effects

### Requirement: Deterministic Adapters Exercise The Full Runtime
Office Graph SHALL provide deterministic model and tool adapters for local tests
and normal verification.

#### Scenario: Verification runs without hosted provider
- **WHEN** the canonical test suite executes agent workflows
- **THEN** deterministic adapters MUST exercise success, retry, terminal,
  malformed-output, approval, and cancellation behavior without network access
