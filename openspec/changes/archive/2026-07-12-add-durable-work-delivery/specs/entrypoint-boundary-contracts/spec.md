## ADDED Requirements

### Requirement: Durable Worker And Realtime Entrypoints Fail Closed

Office Graph SHALL keep Oban workers and realtime subscription handlers thin,
scope-aware, and fail closed.

#### Scenario: Oban worker receives a job

- **WHEN** a durable worker loads event, operation, or target identity from job
  arguments
- **THEN** it MUST validate the typed argument shape and scope, call the owning
  public context, and classify the result without writing another domain's
  truth tables directly

#### Scenario: Realtime subscriber joins

- **WHEN** a session requests a projection invalidation subscription
- **THEN** the entrypoint MUST validate the current request session and target
  scope through the authorization boundary before registering delivery
