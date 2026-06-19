## ADDED Requirements

### Requirement: Internal Agent Runtime

Office Graph SHALL include an internal agent runtime as a core product
capability.

#### Scenario: Agent runtime scope is planned

- **WHEN** the runtime is designed
- **THEN** it must support graph-aware conversations, automatic review agents,
  proposed graph changes, run records, findings, tool approvals, and durable
  provenance

#### Scenario: External tools are integrated

- **WHEN** Office Graph uses external coding, review, design, automation, or
  AI tools
- **THEN** those tools must be represented as integrations or external
  executors without replacing the need for Office Graph's own graph-aware
  runtime

### Requirement: Node-Scoped Embedded Agents

The agent runtime SHALL support conversations scoped to selected graph items.

#### Scenario: User chats from a graph item

- **WHEN** a user starts a conversation from a selected node, edge, artifact,
  check, run, packet, requirement, decision, or review finding
- **THEN** the embedded agent must receive only the authorized context relevant
  to that selected item and must record generated suggestions or proposed
  changes with provenance

### Requirement: Automatic Agents Attached To Graph Scope

The agent runtime SHALL allow automatic agents to attach to graph items,
events, and review-ready scopes.

#### Scenario: Task completion triggers review

- **WHEN** a task, packet, run, commit, PR, campaign, design asset, finance
  item, or other graph item reaches a configured trigger state
- **THEN** attached automatic agents may run according to policy and record
  findings, checks, questions, evidence, or proposed changes

#### Scenario: Parent-level review runs

- **WHEN** child graph items pass review independently
- **THEN** a parent-level agent must be able to review the combined scope for
  conflicts, integration problems, policy violations, or missing evidence

### Requirement: Structured Output And Tool Separation

The runtime SHALL separate model output generation from trusted tool execution.

#### Scenario: Smaller or lower-trust model participates

- **WHEN** a smaller or lower-trust model is used inside an agent workflow
- **THEN** it must produce structured output for a parent agent or trusted
  runtime component instead of receiving direct tool access by default

#### Scenario: Tool action is requested

- **WHEN** an agent requests an action such as modifying graph state, editing
  files, pushing commits, posting comments, calling external APIs, waiving
  checks, or exporting data
- **THEN** the runtime must evaluate the action against authorization,
  autonomy policy, tool scope, integration scope, and approval requirements

### Requirement: Agent Runs Are Durable And Auditable

Every meaningful agent execution SHALL be represented as a run with durable
events and provenance.

#### Scenario: Agent executes work

- **WHEN** an agent runs
- **THEN** the system must record the triggering graph item, principal,
  delegator when applicable, model/provider choices, prompt or prompt policy
  reference, tools requested, tools used, outputs, findings, proposed changes,
  approvals, errors, and resulting evidence according to organization data
  controls

### Requirement: Agent Library Expansion Path

The runtime SHALL preserve a path to specialized agents and a future
marketplace without making untrusted agents unsafe.

#### Scenario: New specialized agent is added

- **WHEN** an agent such as code review, security review, spec review, design
  review, campaign review, brand review, finance review, or operations review
  is added
- **THEN** it must declare attachment points, required capabilities, allowed
  tools, input contracts, output contracts, data controls, and review gates
