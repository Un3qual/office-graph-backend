## ADDED Requirements

### Requirement: Durable identifiers are database-generated UUIDv7
Ordinary durable Office Graph records SHALL receive UUIDv7 primary keys from
PostgreSQL, while explicit caller-supplied identifiers SHALL remain available
only for deterministic replay, imports, fixtures, or workflows that prove the
identifier is required before insertion.

#### Scenario: Ordinary Ash create omits an identifier
- **WHEN** an Ash create action inserts a durable record without an explicit primary key
- **THEN** PostgreSQL MUST generate a valid UUIDv7 and return it to the action

#### Scenario: Deterministic identifier is required
- **WHEN** replay, import, a fixture, or a multi-record workflow requires a stable identifier before insert
- **THEN** the owning private action MAY accept an explicit valid UUID while preserving uniqueness and authorization invariants

#### Scenario: Application UUID default is proposed
- **WHEN** a resource primary key or ordinary create path proposes `Ecto.UUID.generate`, `Ash.UUID.generate`, `Ash.UUIDv7.generate`, or another application default
- **THEN** architecture verification MUST reject it unless the exact pre-insert requirement is documented and tested

#### Scenario: Sharding is introduced later
- **WHEN** Office Graph partitions data across database shards
- **THEN** UUIDv7 MUST remain an opaque durable identifier and the design MUST choose an explicit tenant or scope distribution key rather than assuming UUID ordering determines shard placement
