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

The first implementation task remains to verify current Absinthe/AshGraphql
schema compatibility with Relay object identity, connection-compatible
pagination, fragments, generated TypeScript, mutation payloads, and test
ergonomics before the operator route migration depends on Relay.
