## ADDED Requirements

### Requirement: Agent Definitions Are Approved Product Configuration
Office Graph SHALL store agent definitions with stable key, lifecycle, agent
principal, supported modes, requested capabilities, model adapter, tool
allowlist, and default autonomy envelope.

#### Scenario: OpenSpec review agent is installed
- **WHEN** the runtime migration runs
- **THEN** the canonical OpenSpec-review definition MUST exist without an
  application seed and MUST allow only its declared read-only tools and
  proposal/evidence outputs

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

### Requirement: Agent Definitions Do Not Store Secrets
Agent definitions SHALL reference credential metadata and secret-store keys
without containing secret values.

#### Scenario: Adapter requires a credential
- **WHEN** an agent definition selects a model or tool adapter requiring secret
  material
- **THEN** the definition MUST store only an authorized credential reference and
  MUST NOT expose secret material through APIs or projections
