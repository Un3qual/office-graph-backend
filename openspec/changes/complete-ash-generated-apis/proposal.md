## Why

Office Graph currently mounts AshGraphql and AshJsonApi but still routes most
product API behavior through hand-written Absinthe types, resolvers, Phoenix
controllers, serializers, and a shared `operator_commands` compatibility
layer. The unreleased product should complete the generated API migration now,
before direct-database remediation makes those duplicate transport paths more
expensive to untangle.

## What Changes

- **BREAKING** Let AshGraphql own Relay global ID encoding, generated resource
  objects, resource-node loading, and Relay connections for Ash-backed reads;
  restrict custom Node resolution to named mixed projection objects that
  cannot be represented by an Ash resource read.
- Expose suitable resource actions and typed generic actions through owning Ash
  domains, including Relay ID translation for action arguments, while retaining
  custom GraphQL code only for named mixed-resource projections that generated
  Ash APIs cannot express safely.
- Replace hand-written relationship loaders with declarative Ash relationships
  and generated loading; any remaining Absinthe dataloader field must use the
  direct `resolve: dataloader(...)` form without a wrapper resolver.
- Expand AshJsonApi domain routes and relationship routes for supported
  resource-shaped external API behavior; keep webhooks and genuinely
  orchestration-shaped integration commands as thin custom exceptions.
- **BREAKING** Remove the shared `OfficeGraphWeb.OperatorCommands`
  compatibility namespace and retire duplicated GraphQL resolver, JSON
  controller, input, error, and serializer code as each operation moves to an
  Ash-generated declaration or a narrowly owned transport exception.
- Update route-owned Relay operations, generated schema artifacts, and API
  tests to the resulting schema without preserving unused pre-release field
  names or response envelopes.
- Add structural verification that rejects manual Node dispatch, redundant
  generated-resource objects, wrapper dataloader resolvers, and undocumented
  manual API compatibility paths.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ash-api-surface`: Define the completed generated API state, AshGraphql-owned
  Relay Node behavior, declarative relationship loading, AshJsonApi route
  coverage, and the narrow terminal set of custom transport exceptions.

## Impact

- Affects Ash domain/resource GraphQL and JSON API declarations,
  `OfficeGraphWeb.GraphQL`, `OfficeGraphWeb.JsonApi`, router composition, Relay
  schema and generated artifacts, and API conformance tests.
- Removes the `OfficeGraphWeb.OperatorCommands` compatibility layer and manual
  transport modules that become redundant.
- Preserves owning domain actions, authorization, operation correlation,
  idempotency, concurrency, audit, revision, and safe error behavior.
- Does not add product features, change authentication, remove direct database
  access, rebaseline migrations, or add WorkOS.
