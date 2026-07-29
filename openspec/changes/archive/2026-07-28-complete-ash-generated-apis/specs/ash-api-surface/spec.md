## ADDED Requirements

### Requirement: Generated Ash API migration has a terminal state
Office Graph SHALL complete the AshGraphql and AshJsonApi migration without a
shared manual compatibility API layer.

#### Scenario: Resource-shaped API path exists
- **WHEN** GraphQL or JSON API reads or mutates an Ash-owned resource, relationship, calculation, aggregate, or action
- **THEN** the owning domain MUST expose it through AshGraphql or AshJsonApi unless the accepted custom-path inventory proves the pinned package cannot express the required behavior safely

#### Scenario: Generated migration completes
- **WHEN** the final generated API replacement is verified
- **THEN** `OfficeGraphWeb.OperatorCommands`, GraphQL or JSON API `operator_commands` folders, duplicate resource object definitions, and compatibility aliases MUST NOT remain

#### Scenario: Manual API path remains
- **WHEN** a hand-written Absinthe field or Phoenix JSON route remains after migration
- **THEN** it MUST be a named mixed-projection, webhook, or provider-callback exception with an owning capability, public domain or projection contract, safety tests, and evidence that generated Ash APIs are insufficient

### Requirement: Ash owns resource Relay behavior
AshGraphql SHALL own global ID encoding, generated resource object types,
resource node loading, and connection pagination for Ash-backed GraphQL reads.

#### Scenario: Stable Ash resource is exposed
- **WHEN** a stable Ash resource record is returned by GraphQL
- **THEN** its generated object MUST implement Relay Node with an opaque global `id` and authorized refetch through its owning Ash read action

#### Scenario: Growing Ash resource list is exposed
- **WHEN** a generated GraphQL list can grow beyond one bounded response
- **THEN** its owning read action and GraphQL declaration MUST use keyset-backed Relay connection pagination

#### Scenario: Relay ID is accepted by an action
- **WHEN** a generated action argument identifies another GraphQL resource
- **THEN** the declaration MUST use `relay_id_translations` and MUST reject malformed, raw, cross-type, missing, or unauthorized identifiers safely

#### Scenario: Stable mixed projection is exposed
- **WHEN** a stable mixed-resource projection cannot be represented safely as an Ash resource read
- **THEN** it MAY use an Absinthe Relay `node object` only if it has opaque identity, authorized refetch, an accepted custom-path entry, and no duplicate Ash resource object

#### Scenario: Nested projection value has no independent identity
- **WHEN** a nested value exists only within one projection response and has no independent lifecycle or refetch contract
- **THEN** it MUST remain an ordinary typed object rather than receive an invented Relay Node identity

### Requirement: Commands are generated from owning Ash actions
Commands exposed through both GraphQL and JSON API SHALL use one typed generic
or resource action on the command's owning Ash resource.

#### Scenario: Step-specific command is exposed
- **WHEN** GraphQL or JSON API exposes a current step-specific product command
- **THEN** the owning Ash action MUST define its public arguments and validation, receive the authenticated actor, call the existing public domain command, and return an Ash resource, action metadata, or an explicitly typed result

#### Scenario: Both transports expose a command
- **WHEN** a command is available through GraphQL and JSON API
- **THEN** AshGraphql and AshJsonApi MUST expose the same owning Ash action rather than separate resolver and controller implementations

#### Scenario: Command returns a resource
- **WHEN** a command result is an Ash resource record
- **THEN** GraphQL and JSON API MUST use the generated resource type instead of a hand-written command-result object with duplicate fields

#### Scenario: Command returns multiple values
- **WHEN** a command genuinely returns multiple independent records or operation facts
- **THEN** it MUST use action metadata or a responsibility-owned typed result struct and MUST NOT return an untyped map or transport-owned DTO

### Requirement: Generated APIs use typed Ash errors
Office Graph SHALL represent safe command failures as typed Ash errors that
both generated API packages can serialize.

#### Scenario: Domain command returns a stable failure
- **WHEN** a generated action encounters authorization, validation, not-found, idempotency, lifecycle, or concurrency failure
- **THEN** it MUST return a typed Ash error with safe code, field or path when applicable, and non-sensitive detail

#### Scenario: GraphQL serializes a domain error
- **WHEN** AshGraphql returns a typed command failure
- **THEN** the error MUST be converted through `AshGraphql.Error` and any owning-domain error handler without a central web-layer switch over all commands

#### Scenario: JSON API serializes a domain error
- **WHEN** AshJsonApi returns the same typed command failure
- **THEN** the error MUST be converted through `AshJsonApi.ToJsonApiError` and any owning-domain error handler with equivalent code and safe meaning

### Requirement: Relationship fields use declarative loading
GraphQL and JSON API relationship fields SHALL be generated from Ash
relationships, calculations, aggregates, or accepted typed projection actions.

#### Scenario: Ash relationship is exposed
- **WHEN** an API field returns records available through an Ash relationship
- **THEN** the generated field and package loader MUST be used instead of a hand-written resolver that fetches the related records

#### Scenario: Custom Absinthe dataloader is necessary
- **WHEN** an accepted custom projection field requires Absinthe Dataloader outside AshGraphql
- **THEN** the field MUST declare `resolve: dataloader(Source)` directly and MUST NOT add a block field or wrapper resolver that only delegates to the dataloader

#### Scenario: JSON API relationship is supported
- **WHEN** an external JSON API client needs a supported resource relationship
- **THEN** the owning AshJsonApi domain MUST expose a generated related or relationship route with the resource's authorization and lifecycle rules

#### Scenario: Signal graph spine is read
- **WHEN** an authorized client reads a Signal and follows its graph item,
  tasks, review findings, or verification checks
- **THEN** AshGraphql MUST return generated Relay resource nodes and
  connections, and AshJsonApi MUST expose the corresponding generated resource
  and related routes

#### Scenario: Graph relationship endpoints require redaction
- **WHEN** a client traverses relationships whose opposite endpoint may not be
  authorized
- **THEN** the generated GraphItem read MUST remain the resource identity
  surface while the classified redacted relationship-view projection filters
  or redacts endpoints without exposing the underlying GraphRelationship
  resource as an unrestricted generated read

#### Scenario: Run conversation resources are read
- **WHEN** an authorized client reads a run conversation, its messages, agent
  executions, approval requests, or context-expansion requests
- **THEN** AshGraphql MUST return generated Relay resource nodes and
  connections, AshJsonApi MUST expose generated resource and related routes,
  and the mixed operator projection MUST retain only command affordances,
  source watermarking, and independently redacted message-context facts

## MODIFIED Requirements

### Requirement: Manual API Migration Ledger

Office Graph SHALL replace the temporary manual migration ledger with a
terminal custom-path inventory containing only accepted mixed-projection,
webhook, and provider-callback exceptions.

#### Scenario: Manual API path remains live

- **WHEN** a manual Absinthe root field, Phoenix JSON route, serializer, or
  transport-specific resolver remains after this migration
- **THEN** the implementation MUST record its owning capability, exception
  class, reason the pinned AshGraphql or AshJsonApi package is insufficient,
  public domain or projection contract, safety tests, and retirement condition
  when the limitation is temporary

#### Scenario: New manual API path is proposed

- **WHEN** a later change proposes new custom GraphQL or JSON API behavior
- **THEN** the accepted design MUST classify it as a mixed-projection,
  webhook, or provider-callback exception and MUST prove why generated Ash API
  declarations are insufficient

#### Scenario: Compatibility path has no terminal exception

- **WHEN** a manual resolver, controller, serializer, input parser, error
  classifier, object definition, field alias, or route exists only to preserve
  the pre-release API migration shape
- **THEN** canonical verification MUST reject it and require deletion
