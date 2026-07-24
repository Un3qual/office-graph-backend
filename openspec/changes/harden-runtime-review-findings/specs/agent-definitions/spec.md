## MODIFIED Requirements

### Requirement: Agent Definitions Are Approved Product Configuration
Office Graph SHALL store agent definitions with stable key, lifecycle, agent
principal, supported modes, requested capabilities, model adapter, tool
allowlist, and default autonomy envelope.

#### Scenario: Run review agent is installed
- **WHEN** the runtime migration runs on a fresh database
- **THEN** the canonical definition MUST exist without an application seed with
  key exactly `run-review`, display name exactly `Run Review`, and model adapter
  exactly `deterministic`

#### Scenario: Legacy run review definition is upgraded

- **WHEN** a database containing the legacy `openspec-review` definition runs
  the forward reconciliation migration
- **THEN** the existing definition identity MUST be preserved under the
  canonical `run-review` key and its configuration MUST match a fresh install

#### Scenario: Run review agent authority is loaded

- **WHEN** the canonical `run-review` definition is loaded for binding or
  invocation
- **THEN** its tool allowlist MUST be empty and its requested capabilities MUST
  be exactly `agent.invoke`, `agent.model.generate`, `proposal.create`, and
  `evidence.suggest`, with no additional capability

#### Scenario: Definition is bound to an organization
- **WHEN** an authorized local owner invokes the narrow binding command
- **THEN** Office Graph MUST bind the definition and backend agent principal to
  that organization and current workspace without exposing a generic
  agent-admin mutation

#### Scenario: Active definition binding is requested again

- **WHEN** an authorized owner repeats the narrow binding command for a
  definition already bound to the same organization and workspace
- **THEN** Office Graph MUST return the active scoped binding without requiring
  the original operation identity or creating a duplicate binding

#### Scenario: Inactive definition is invoked
- **WHEN** a definition or organization binding is disabled or revoked
- **THEN** the runtime MUST reject new execution and preserve historical
  definition references
