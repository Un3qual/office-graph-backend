## GraphQL Client Decision

Relay is selected as the product GraphQL client model for this change.

Use Relay for product GraphQL server state, including the operator workflow
route migration. Product routes should use Relay environment setup, root or
route queries, fragments, generated Relay types, connection-compatible
pagination where lists can grow, and mutation payloads or explicit invalidation
paths that keep the Relay store coherent.

TanStack Query plus generated GraphQL operation types is out of implementation
scope for product GraphQL data in this change. Do not add TanStack Query as a
parallel cache for the same product GraphQL records.

The first implementation task is to verify current Absinthe/AshGraphql schema
compatibility with Relay object identity and connection-compatible pagination
before the operator route migration depends on Relay. Relay compiler,
generated TypeScript, fragment, and mutation payload ergonomics remain tied to
the frontend Relay compiler setup.

## Server Relay Contract

The backend GraphQL schema uses the Hex `absinthe_relay` package for Relay
helpers. AshGraphql already provides some Relay foundation types, so the schema
must avoid duplicate `Node` and `PageInfo` definitions by making a single owner
explicit.

Stable product GraphQL objects should expose opaque Relay Node IDs on `id`.
Raw database/resource identifiers should only appear in explicit fields when a
command input, audit trace, or migration compatibility path requires them.

Product GraphQL lists that can grow should expose Relay-style connections with
`edges`, per-edge `cursor`, and `pageInfo`. Legacy list fields can remain only
as temporary compatibility paths while the operator route migrates to Relay.

Current implementation status:

- `absinthe_relay` is added as a backend dependency.
- The current generated product GraphQL reads (`listSignals`,
  `listWorkPackets`, and `listWorkRuns`) now return Relay connections and
  expose opaque global `id` values.
- Generated `Signal`, `WorkPacket`, and `WorkRun` objects can be refetched
  through the root `node(id:)` field.
- `OperatorWorkflowItem` is Node-compatible through a global Relay `id`.
- `operatorWorkflowItems(first:, after:)` exposes operator workflow items as a
  forward Relay connection.
- The existing `operatorInbox` field remains for the current pre-Relay
  frontend and should be retired during the operator route migration.
