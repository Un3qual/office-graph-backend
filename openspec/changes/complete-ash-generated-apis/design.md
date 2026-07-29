## Context

The pinned API stack is Ash 3.29.3, AshGraphql 1.9.4, AshJsonApi 1.6.6,
Absinthe 1.11.0, and Absinthe Relay 1.6.0. The local documentation for those
versions confirms that:

- `relay? true` generates Node implementations and Relay connections;
- `relay_ids?: true` generates global IDs and `relay_id_translations` converts
  action inputs back to resource identifiers;
- AshGraphql generic actions generate typed queries and mutations and load
  returned records;
- action metadata and typed struct types can expose structured command results;
- AshJsonApi `route` exposes generic actions with any return type, while
  resource and relationship helpers generate JSON:API-shaped routes;
- both packages support custom error protocols and domain error handlers.

Office Graph already generates Relay resource objects and list reads for
Signal, WorkPacket, and WorkRun, and mounts three AshJsonApi read collections.
However, the root GraphQL schema also imports 18 hand-written command
mutations, duplicate command-result object types, and a manual node dispatcher.
The Phoenix router exposes the same 18 commands through six custom controller
modules. Both transports share a roughly 500-line error classifier and a
central input parser under `OfficeGraphWeb.OperatorCommands`.

The current mixed-resource operator workflow, redacted relationship view, and
integration-health reads are legitimate projection-shaped APIs. Resource-shaped
packet, run, conversation, relationship, and command result data should not be
manually recreated around them.

## Goals / Non-Goals

**Goals:**

- Make owning Ash resources and generic actions the shared API contract for
  both GraphQL and JSON API.
- Ensure every stable resource-shaped GraphQL object has generated Relay Node
  identity and every growing resource list uses a generated Relay connection.
- Replace manual relationship loading and duplicate resource object types with
  generated Ash relationships and field loading.
- Remove the `operator_commands` compatibility namespaces and their duplicated
  resolver/controller/input/error/serializer paths.
- Keep only named, tested custom transport code for mixed projections,
  webhooks, and response shapes that the pinned Ash packages cannot express.
- Preserve authorization, operation correlation, idempotency, concurrency,
  audit, revision, and safe error semantics.

**Non-Goals:**

- Rewrite domain command internals or remove their current database-access debt.
- Rebaseline migrations, add database schema, or change PostgreSQL.
- Add product behavior, authentication changes, WorkOS, SSO, or Directory Sync.
- Convert mixed projections into artificial persisted resources merely to
  avoid a small custom transport boundary.
- Preserve unused pre-release GraphQL field names, JSON response envelopes, or
  the old manual command routes as compatibility aliases.

## Decisions

### 1. Classify every current path by the narrowest Ash API mechanism

Each GraphQL field and JSON route will be classified as one of:

1. generated resource read or relationship;
2. generated resource create/update/destroy action;
3. generated generic action over an owning resource;
4. custom mixed-projection read;
5. custom webhook or provider callback.

The first three classes move to AshGraphql/AshJsonApi declarations. The last
two remain only in transport-first, capability-owned modules with structural
inventory evidence. A manual resource read, duplicate resource object, or
controller/resolver pair is not an exception.

Alternative considered: mechanically move the current files out of
`operator_commands` while retaining their implementation. Rejected because it
would improve folder names without removing the duplicated API architecture.

### 2. Use owning-resource generic actions for command-shaped APIs

Step-specific commands that already call public context functions will gain a
public generic Ash action on the resource that owns the command result. The
action will:

- declare typed public arguments and built-in validations;
- receive the authenticated session context as the Ash actor;
- start or validate the named operation and call the existing public context
  command;
- return an Ash resource record, action metadata, or an explicitly typed
  result struct;
- return typed Ash errors rather than transport-owned tuples.

AshGraphql domain mutations will expose those actions with
`relay_id_translations` for resource-ID arguments. AshJsonApi domain `route`
declarations will expose the same actions under `/api/v1/commands/**`.
Resource-returning actions may use standard JSON:API helpers when the response
is naturally a resource document.

This keeps one argument and execution contract without moving Phoenix or
Absinthe concerns into domains. It also prepares later transaction cleanup
without changing that transaction behavior in this change.

Alternative considered: create one generic API command resource containing all
18 actions. Rejected because it would be a transport-shaped god object with no
domain ownership.

Alternative considered: keep custom resolvers and controllers because the
commands span more than one record. Rejected because both pinned packages
explicitly support generic actions and typed struct results for this case.

### 3. Keep the documented Absinthe Relay integration only for true projection nodes

The schema currently uses Absinthe Relay with
`define_relay_types?: false`, which is the integration explicitly documented by
AshGraphql when a schema also defines non-Ash Relay types. That configuration
is not itself migration debt.

Ash-backed objects will use generated types, global ID encoding, Relay
connections, and Ash action-based node loading. Manual node resolution will be
restricted to stable mixed-projection objects such as the operator workflow
item and redacted relationship view. Every such exception must use
`node object`, have an opaque ID, support authorized refetch, and be named in
the final custom-path inventory.

Nested view values without independent identity will remain ordinary objects;
inventing Node IDs for them would misrepresent their lifecycle.

Alternative considered: remove Absinthe Relay and force all projections into
Ash resources. Rejected because it would create artificial resource modules
for ephemeral mixed read models solely to satisfy transport mechanics.

### 4. Let relationships drive field loading

Fields backed by an Ash relationship, calculation, or aggregate will be exposed
from the generated resource type and loaded by AshGraphql. Manual resolver
functions that only fetch a related record or collection will be removed.

If a remaining custom projection field genuinely uses Absinthe Dataloader, the
field will declare `resolve: dataloader(Source)` directly. It will not use a
block field plus a one-line resolver wrapper. The current code has no live
Absinthe Dataloader use, so the structural rule primarily prevents regression.

Alternative considered: preserve wrapper resolvers for naming consistency.
Rejected because they add indirection without policy, validation, or mapping.

### 5. Replace transport-wide input and error switches with Ash types and errors

Action arguments, Ash.TypedStruct input types, and action validations replace
the central command-name input parser. Resource outputs use generated GraphQL
and JSON:API types; non-resource results use narrowly scoped typed structs with
behavior in their owning modules.

Stable safe command errors become typed Ash errors with
`AshGraphql.Error` and `AshJsonApi.ToJsonApiError` implementations. Domain
error handlers may sanitize or rename fields, but a single web-layer switch
over every domain error will be removed.

Resource-bearing result types are compiled with the action-owning resource
rather than in a standalone result file that embeds that resource. Aggregate
commands are declared on the aggregate/output resource, and their runners may
remain in the capability that owns the behavior. This avoids reciprocal
compile dependencies while preserving the public capability boundary.

When one command affects resources across capability boundaries, its typed
result returns the primary resource, operation metadata, and `affectedIds`.
GraphQL callers refetch those generated Relay nodes instead of receiving
duplicate cross-boundary records in the command payload. This keeps generated
resource reads authoritative and prevents result structs from becoming a
second read model.

Alternative considered: keep the shared classifier behind the generated
actions. Rejected because it would leave transport-independent domain outcomes
coupled to one compatibility namespace and would not use the packages' error
extension points.

### 6. Generated JSON API routes are external integration surfaces

AshJsonApi will own resource reads, supported relationships, and generic action
routes. The product frontend continues to use GraphQL; frontend JSON adapters
will not be retained as a fallback.

GitHub webhooks remain a custom controller because signature verification and
provider callback semantics precede an Ash action. A projection route may
remain custom only when a generated generic action cannot preserve its mixed,
policy-filtered result safely. Every remaining route must call a public domain
or projection boundary and own no business rules.

### 7. Structural verification defines the terminal state

Canonical verification will reject:

- `OfficeGraphWeb.OperatorCommands` and transport folders named
  `operator_commands`;
- duplicate manual GraphQL object definitions for generated Ash resources;
- manual node dispatch for Ash resource types;
- wrapper dataloader resolvers;
- unclassified manual Absinthe root fields or Phoenix JSON routes;
- JSON API resource endpoints that bypass available AshJsonApi declarations.

The final inventory records only terminal custom projection, webhook, and
provider-callback exceptions. It is not a temporary compatibility ledger.

## Risks / Trade-offs

- **Generated schema names and envelopes will change.** → Update route-owned
  Relay operations and JSON API tests in the same slice; the product is
  unreleased, so do not add aliases for unused old names.
- **A generic action could accidentally weaken command safety.** → Keep the
  existing public domain command as the execution boundary and prove
  authorization, idempotency, conflict, audit, revision, and race behavior
  before deleting each old transport.
- **Typed result structs could become another DTO layer.** → Return Ash resource
  records or action metadata first; introduce a result struct only when one
  command genuinely returns multiple independently meaningful values, and use
  `affectedIds` plus authoritative node refetches for cross-boundary changes.
- **Relay IDs can be double-decoded or accepted as raw UUIDs.** → Use
  `relay_id_translations` for generated actions and negative tests for raw,
  malformed, cross-type, missing, and unauthorized IDs.
- **Ash package error defaults may expose or hide different detail.** → Implement
  explicit error protocols for domain errors and retain safe-code tests at
  both transports.
- **Removing manual paths in one cut can obscure regressions.** → Migrate by
  owning context, prove the new generated path, switch callers, then delete the
  corresponding manual code before moving to the next context.

## Migration Plan

1. Add failing structural and schema tests for the terminal API boundary and
   capture a classified inventory of current manual paths.
2. Complete generated resource reads, relationships, Relay Node behavior, and
   frontend operations for WorkGraph, WorkPackets, Runs, and conversations.
3. Introduce owning-resource generic actions and typed errors/results for each
   command group; expose them through both AshGraphql and AshJsonApi.
4. Migrate frontend and integration tests context by context, deleting each
   superseded resolver, controller, input type, result object, and serializer.
5. Move the few remaining custom projections and webhook paths into their
   capability-owned namespaces and delete all `operator_commands` paths.
6. Regenerate Relay artifacts, run focused API/authorization/concurrency tests,
   and run the complete canonical verification gate.

Rollback is a normal revert before release. Database rollback is unnecessary
because this change does not alter persisted schema.

## Open Questions

None. The generated-first boundary, official Absinthe Relay integration,
generic-action sharing, error protocols, and narrow custom exceptions are
supported by the pinned package documentation and the approved remediation
sequence.
