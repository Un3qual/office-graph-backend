## MODIFIED Requirements

### Requirement: Directory deliveries are replay-safe and ordered

Office Graph SHALL process one logical WorkOS directory event once and SHALL
not allow stale or earlier accepted provider state to overwrite a newer
accepted state.

#### Scenario: Identical event is delivered twice

- **WHEN** the same provider event ID and content hash are received again
- **THEN** Office Graph MUST return a successful replay result without enqueueing or applying a second mutation

#### Scenario: Event ID content changes

- **WHEN** an existing provider event ID is reused with a different content hash
- **THEN** Office Graph MUST record or return a deterministic conflict and MUST NOT apply the changed payload

#### Scenario: Older event arrives after newer event

- **WHEN** a user, group, or membership event has an older provider update time than the current accepted record
- **THEN** Office Graph MUST preserve the newer state and complete the older event with a bounded stale result

#### Scenario: Distinct events have equal provider timestamps

- **WHEN** distinct user, group, or membership events have the same provider update time
- **THEN** Office Graph MUST use durable receipt order and provider event identity as a deterministic tie-breaker so the later accepted state wins regardless of worker execution order

#### Scenario: Worker fails after receipt

- **WHEN** asynchronous application of an accepted directory event fails
- **THEN** Oban MUST retry the idempotent event action without creating duplicate resources or bypassing the event's original operation and archive provenance
