# realtime-delivery Specification

## Purpose

Define realtime delivery ownership, authorization, and projection-reconciliation
rules for Office Graph product screens and routes.

## Requirements

### Requirement: Realtime Delivery Uses Domain Events

Office Graph SHALL deliver realtime updates from domain events, projection
changes, and approved runtime events rather than treating Postgres or API
controllers as the application realtime bus.

#### Scenario: Domain state changes

- **WHEN** a graph item, work packet, run, verification check, evidence item,
  conversation, projection, change proposal, or agent runtime state changes
- **THEN** the owning domain or projection layer MUST publish a typed event
  through the realtime boundary after authorization-relevant durable state is
  committed

#### Scenario: Database state changes outside product workflow

- **WHEN** maintenance, backfill, replay, or repair work changes durable state
- **THEN** it MUST either publish approved projection invalidation events or
  mark affected projections stale rather than relying on database notifications
  as the sole customer-facing realtime mechanism

### Requirement: Subscriptions And Channels Are Authorization Filtered

Office Graph SHALL filter realtime delivery through the same tenant, scope,
sensitivity, relationship, and policy rules used by reads and projections.

#### Scenario: Subscriber receives projection update

- **WHEN** a user, agent, service account, or integration subscribes to a graph
  projection, node conversation, work packet, run, or verification view
- **THEN** each delivered event MUST be scoped, authorized, and redacted or
  omitted according to the subscriber's current visibility policy

#### Scenario: Authorization changes during subscription

- **WHEN** a principal loses access, gains access, changes workspace, receives a
  temporary grant, or crosses a sensitivity boundary while subscribed
- **THEN** the realtime layer MUST stop, alter, redact, or reauthorize delivery
  before exposing new restricted data

### Requirement: Realtime Streams Have Explicit Ownership

Office Graph SHALL assign each realtime topic, subscription field, channel,
and projection invalidation stream to an owning domain or projection context.

#### Scenario: New realtime topic is added

- **WHEN** a design introduces a realtime topic for inboxes, node views,
  conversations, runs, verification, agent runtime status, or review screens
- **THEN** the design MUST identify the owner, source events, authorization
  filter, payload shape, backfill/read-after-connect behavior, and stale-cache
  invalidation behavior

#### Scenario: Transport-specific realtime message format differs

- **WHEN** Absinthe subscriptions and Phoenix Channels expose different
  message formats for the same event
- **THEN** both transports MUST derive from the same domain/projection event
  contract and differ only in transport mapping

### Requirement: Realtime Payloads Are Projection Hints

Office Graph SHALL treat realtime payloads as projection updates or invalidation
hints, not as authoritative replacements for durable reads.

#### Scenario: Client receives realtime event

- **WHEN** a frontend receives a realtime event for graph, work packet, run,
  review, evidence, or agent runtime state
- **THEN** the event MUST include enough identity, version, or invalidation
  information for the client to reconcile through the authorized projection API
  when needed

#### Scenario: Event delivery is missed

- **WHEN** a client reconnects after missed events, stale cache, or network
  interruption
- **THEN** the client MUST be able to recover by reading the authoritative
  authorized projection or resource API state
