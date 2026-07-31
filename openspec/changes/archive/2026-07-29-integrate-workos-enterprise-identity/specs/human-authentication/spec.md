## ADDED Requirements

### Requirement: Human login selects a configured provider before redirect

Office Graph SHALL select the human authentication provider and any enterprise
connection before redirecting the browser and SHALL carry that selection only
inside the bounded one-time login transaction.

#### Scenario: Local OIDC login begins

- **WHEN** a developer or deployment uses the configured generic OIDC entry
  point
- **THEN** Office Graph MUST retain the existing OIDC discovery, nonce, PKCE,
  callback validation, external identity reconciliation, and durable session
  behavior

#### Scenario: WorkOS enterprise login begins

- **WHEN** a human starts login through an active WorkOS enterprise connection
- **THEN** Office Graph MUST use the WorkOS SSO adapter for external exchange
  while using the same internal principal, scope, session, lifecycle, and
  authentication-evidence boundaries as generic OIDC

#### Scenario: Provider selection is unavailable

- **WHEN** the selected provider or enterprise connection is absent, disabled,
  incomplete, or inconsistent with the stored login transaction
- **THEN** Office Graph MUST fail closed without falling back to another
  provider or issuing a session under a different tenant
