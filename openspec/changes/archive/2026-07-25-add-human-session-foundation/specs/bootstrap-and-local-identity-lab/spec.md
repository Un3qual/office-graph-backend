## ADDED Requirements

### Requirement: Explicit Bootstrap Is Not Request Authentication

Office Graph SHALL keep first-owner bootstrap as an explicit controlled action
and SHALL NOT invoke it to authenticate normal product or API requests.

#### Scenario: Unauthenticated product request arrives

- **WHEN** a request without a valid human session reaches a product page
- **THEN** Office Graph MUST redirect the browser to the configured login path
  and MUST NOT create or assign a local owner

#### Scenario: Unauthenticated API request arrives

- **WHEN** a request without a valid human session reaches GraphQL or the JSON
  API
- **THEN** Office Graph MUST leave the request without a human actor and MUST
  NOT invoke local-owner bootstrap

#### Scenario: Test or development fixture needs an owner

- **WHEN** a test or developer explicitly invokes the local bootstrap helper
- **THEN** the existing idempotent first-owner fixture behavior MAY create or
  return the controlled local owner and session outside the normal request
  pipeline

### Requirement: Authentik Login Configuration Is Explicit

Office Graph SHALL enable the local Authentik OIDC path only from a complete,
explicit provider configuration.

#### Scenario: OIDC configuration is missing or partial

- **WHEN** a human attempts login without a complete issuer, client, and
  account-linking configuration
- **THEN** login MUST fail closed and MUST NOT fall back to local-owner
  bootstrap
