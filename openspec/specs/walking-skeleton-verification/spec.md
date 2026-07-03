# walking-skeleton-verification Specification

## Purpose

Define the verification contract for the walking skeleton, including backend
quality commands, database prerequisites, end-to-end loop coverage, Boundary
enforcement, authorization and redaction tests, idempotency checks, API smoke
tests, and architecture conformance.

## Requirements

### Requirement: Project Verification Commands

Office Graph SHALL provide repeatable commands for the first backend quality
gate.

#### Scenario: Developer verifies the backend skeleton

- **WHEN** the implementation is complete
- **THEN** the documented verification path MUST run compile, format check,
  tests, Boundary checks, database setup/migration checks, and
  `openspec validate --changes --strict` from the project Nix shell

#### Scenario: Verification requires Postgres

- **WHEN** database-backed verification commands run locally
- **THEN** the verification documentation MUST start or require the Docker
  Compose Postgres service before running Ecto setup, migrations, resource
  tests, API smoke tests, or end-to-end walking-skeleton tests

### Requirement: Walking Skeleton End-To-End Test

Office Graph SHALL include an executable test for the full first product loop.

#### Scenario: End-to-end skeleton test runs

- **WHEN** the test suite executes the primary walking-skeleton scenario
- **THEN** it MUST prove bootstrap, manual intake, raw archive/idempotency,
  change proposal validation/application, task creation, review finding
  creation, required verification check creation, evidence linking,
  verification result creation, and verified completion

### Requirement: Boundary Enforcement Test

Office Graph SHALL verify context boundary discipline in the first backend
cut.

#### Scenario: Boundary verification runs

- **WHEN** the boundary check command runs
- **THEN** it MUST fail if controllers, resolvers, adapters, jobs, tests, or
  another context import private modules instead of public context contracts

### Requirement: Authorization And Redaction Tests

Office Graph SHALL test the first authorization decisions used by the walking
skeleton.

#### Scenario: Principal lacks access

- **WHEN** a principal without the required role, scope, capability, or grant
  attempts to read or mutate walking-skeleton records
- **THEN** the test suite MUST prove the action is denied or redacted and that
  any required authorization decision or audit trace is recorded

### Requirement: Idempotency And Replay Tests

Office Graph SHALL test duplicate manual intake handling.

#### Scenario: Intake is replayed or duplicated

- **WHEN** the same manual intake source identity and replay identity are
  submitted more than once
- **THEN** the test suite MUST prove Office Graph does not create duplicate
  signals, tasks, review findings, checks, evidence, artifacts, or change
  proposals unless an explicit conflict/review path is selected

### Requirement: API Smoke Tests

Office Graph SHALL test both API endpoints against the same domain behavior.

#### Scenario: API smoke tests run

- **WHEN** GraphQL and JSON API smoke tests exercise the walking-skeleton flow
- **THEN** both API endpoints MUST produce equivalent durable state, authorization
  decisions, validation outcomes, and operation correlation linkage

### Requirement: Architecture Conformance Gate

Office Graph SHALL verify that implementation architecture matches accepted
OpenSpec design decisions, not only externally visible behavior.

#### Scenario: Backend verification runs

- **WHEN** `bin/verify-backend` runs for the walking skeleton
- **THEN** it MUST fail if required Ash domains/resources are missing, stable
  product mutations bypass Ash without an approved exception, the direct Ecto
  exception ledger drifts from approved mutation paths, or the implementation
  summary lacks requirement-to-evidence mapping
