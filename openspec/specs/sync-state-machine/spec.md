# sync-state-machine Specification

## Purpose
Define explicit ingestion synchronization states, retries, and terminal outcomes.
## Requirements
### Requirement: Ingestion Sync State Machine
Office Graph SHALL use a shared sync state vocabulary for ingestion and replay.

#### Scenario: Event moves through ingestion
- **WHEN** manual or provider input is processed
- **THEN** the sync state MUST be able to represent received, archived,
  normalized, validated, applied, duplicate, skipped, pending dependency,
  failed retryable, failed terminal, and replayed states

#### Scenario: Provider-specific state exists
- **WHEN** a provider adapter needs provider-local cursor, webhook delivery,
  retry, or reconciliation state
- **THEN** the provider-specific state MUST map back to the shared sync state
  vocabulary for support, replay, audit, and operations
