## ADDED Requirements

### Requirement: Canonical test database logging is quiet by default

Office Graph SHALL suppress Ecto, AshPostgres, and repository query debug logs
during normal test and canonical verification runs while preserving an
explicit opt-in diagnostic mode.

#### Scenario: Canonical test suite passes

- **WHEN** `bin/verify` runs the normal ExUnit suite
- **THEN** query text and bound parameter dumps MUST NOT be emitted for
  successful database operations

#### Scenario: Contributor diagnoses a database failure

- **WHEN** a contributor enables the documented SQL diagnostic switch for a
  focused test run
- **THEN** database query debug logging MUST be available without changing
  tracked configuration

#### Scenario: Logging contract regresses

- **WHEN** a normal test environment emits successful query logs at its
  configured logger level
- **THEN** project-quality verification MUST fail with a focused logging
  configuration diagnostic
