## ADDED Requirements

### Requirement: Projection Invalidations Use One Authorized Contract

Office Graph SHALL publish tenant-scoped projection invalidation hints through
one typed, authorization-filtered contract after durable state commits.

#### Scenario: Authorized subscriber receives invalidation

- **WHEN** a current session subscribes within its organization and workspace
  and a matching committed domain event is dispatched
- **THEN** the subscriber MUST receive only event identity, kind, subject
  identity and version, operation identity, and scope hints needed to refetch an
  authoritative projection

#### Scenario: Subscriber is outside event scope

- **WHEN** a session attempts to subscribe to another organization or an
  unauthorized workspace
- **THEN** Office Graph MUST reject the subscription and MUST NOT reveal whether
  matching events or subjects exist

#### Scenario: Delivery is missed or duplicated

- **WHEN** a client reconnects after missing an invalidation or receives a
  repeated delivery attempt
- **THEN** the event identity MUST support deduplication and the client MUST be
  able to recover by refetching the authorized projection

