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

#### Scenario: Credentialed adapter input is assembled

- **WHEN** an adapter manifest declares required credential kinds
- **THEN** the runtime MUST derive presented kinds from active credential
  metadata captured by the authority snapshot and MUST NOT copy requirements
  from the manifest into the request as proof of authority

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

#### Scenario: Adapter returns a globally valid but undeclared classification

- **WHEN** output is structurally valid but its classification is not allowed by
  the selected manifest
- **THEN** the worker MUST reject it before output routing and MUST NOT create an
  owning-domain effect

### Requirement: Deterministic Adapters Exercise The Full Runtime
Office Graph SHALL provide deterministic model and tool adapters for local tests
and normal verification.

#### Scenario: Verification runs without hosted provider
- **WHEN** the canonical test suite executes agent workflows
- **THEN** deterministic adapters MUST exercise success, retry, terminal,
  malformed-output, approval, and cancellation behavior without network access

### Requirement: Repository Tooling Is Release Configured And Ready
Office Graph SHALL resolve automatic repository-review dependencies from
runtime configuration rather than a build checkout or ambient executable path.

#### Scenario: Runtime starts automatic workers
- **WHEN** the application starts with the OpenSpec-review workflow registered
- **THEN** it MUST validate an absolute immutable repository mount, pinned Git
  and OpenSpec executables, the mounted `HEAD`, `openspec/project.md`, and
  bounded parseable OpenSpec inventory before starting durable workers

#### Scenario: Repository tooling is unavailable
- **WHEN** any configured mount, executable, revision, project artifact, or
  OpenSpec inventory cannot be read safely
- **THEN** application startup MUST fail closed before an automatic job can be
  consumed

#### Scenario: Ambient telemetry configuration is enabled

- **WHEN** the runtime process inherits an environment that enables OpenSpec
  telemetry
- **THEN** both the packaged executable and every application invocation MUST
  force telemetry off so repository reads perform no telemetry configuration
  writes or outbound telemetry requests
