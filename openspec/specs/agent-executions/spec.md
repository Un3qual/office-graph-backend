# agent-executions Specification

## Purpose
TBD - created by archiving change design-runs-and-verification. Update Purpose after archive.
## Requirements
### Requirement: Agent Executions Are Child Runtime Invocations

Office Graph SHALL represent each internal agent runtime invocation as an agent
execution that is normally linked to a parent work run.

#### Scenario: Agent execution starts inside a work run

- **WHEN** Office Graph invokes an internal agent to investigate, plan, propose,
  verify, summarize, or execute one step of selected work
- **THEN** Office Graph MUST create or be able to create an agent execution
  linked to the parent work run, selected sub-objective, invocation mode,
  initiating principal or trigger, agent principal, context package, autonomy
  envelope, and operation context

#### Scenario: Agent execution is not the whole work run

- **WHEN** a work run invokes multiple agents, retries one agent, hands off to a
  human, imports provider status, or waits for verification
- **THEN** each agent invocation MUST remain a child agent execution and MUST
  NOT overwrite the parent work run's selected work, aggregate status, or
  verification result

### Requirement: Agent Execution Authority Is Explicit

Office Graph SHALL record the effective authority boundary for each agent
execution.

#### Scenario: Agent execution authority is evaluated

- **WHEN** an agent execution starts or requests a tool, credential, context
  expansion, external write, change proposal, or domain action
- **THEN** Office Graph MUST evaluate and record delegator or trigger
  authority, agent principal capability, scope, autonomy envelope, tool or
  integration scope, sensitivity labels, temporary grants, and policy result

#### Scenario: Agent execution lacks authority

- **WHEN** the agent execution lacks authority for requested context, tool use,
  credential access, mutation, external write, or verification action
- **THEN** Office Graph MUST deny the step, request approval, request context
  expansion, downgrade to proposal-only behavior, or block the execution
  according to policy

### Requirement: Agent Execution Events Capture Product-Relevant Steps

Office Graph SHALL preserve product-relevant agent execution events without
turning low-level runtime traces into the product timeline by default.

#### Scenario: Agent execution produces durable outputs

- **WHEN** an agent execution selects context, evaluates authority, calls a
  tool, creates a finding, creates a change proposal, emits an evidence
  candidate, requests approval, fails, retries, or completes
- **THEN** Office Graph MUST preserve an agent-execution event or equivalent
  typed reference sufficient to explain the output, failure, or handoff

#### Scenario: Runtime emits low-level traces

- **WHEN** the runtime produces token-level, prompt-debug, worker-debug, or
  provider-specific traces that are not product-relevant
- **THEN** Office Graph MUST NOT require those traces to become
  agent-execution events, though they may be logged or archived according to
  retention and AI data-control policy

### Requirement: Agent Outputs Route To Owning Domain Contracts

Office Graph SHALL treat agent outputs as untrusted structured outputs until
they are validated and routed to the owning domain.

#### Scenario: Agent proposes a mutation

- **WHEN** an agent execution produces a graph or domain mutation suggestion
- **THEN** Office Graph MUST route it through change-proposal validation,
  authorization, approval, and domain-action application rather than letting
  the agent execution write graph truth directly

#### Scenario: Agent produces verification material

- **WHEN** an agent execution produces a finding, check result, summary,
  artifact, monitoring conclusion, or other verification material
- **THEN** Office Graph MUST classify it as a finding, observation, evidence
  candidate, change-proposal input, or another typed output before it can
  satisfy verification
