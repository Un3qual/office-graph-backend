## 1. GraphQL Client Decision

- [x] 1.1 Record Relay as the selected product GraphQL client model in the implementation notes.
- [x] 1.2 Remove TanStack Query plus generated GraphQL operation types from the product GraphQL implementation scope.
- [x] 1.3 Add `absinthe_relay` and verify the operator workflow schema path plus current generated product reads support Relay object identity and connection-compatible pagination before route migration depends on them.
- [x] 1.4 Verify Relay fragments, generated TypeScript, mutation payload shape, and test ergonomics when the frontend Relay compiler path is introduced.

## 2. React Router Framework Mode Foundation

- [x] 2.1 Add React Router Framework Mode configuration under `assets` without changing Phoenix product routing semantics beyond serving the built SPA.
- [x] 2.2 Create the route root, route config, and route-owned operator module using the accepted route-first layout.
- [x] 2.3 Add `AppProviders.tsx` for React application wrappers only, including the Relay provider and any required app/session context.
- [x] 2.4 Keep shared UI shallow under the accepted layout and avoid `platform`, `domains`, `shared/design`, or `shared/ui` folders unless a concrete repeated-code need is documented.

## 3. Operator Route Migration

- [x] 3.1 Move the existing `/operator` React surface into the route-owned module without adding new product behavior.
- [x] 3.2 Replace old operator data hooks or mappers with Relay root queries, fragments, and generated Relay types.
- [x] 3.3 Remove frontend JSON adapter assumptions for operator workflow reads once GraphQL route data covers the current behavior.
- [x] 3.4 Preserve current operator loading, empty, error, selected-row, readiness, run, and verification states.
- [x] 3.5 Remove cosmetic aliases around generated Relay fragment data, use generated types directly at the route data boundary, and keep hand-written route types limited to client-owned state.

## 4. Command Affordance Contract

- [x] 4.1 Rename frontend planning and implementation language from generic "actions" to product commands and UI affordances where it refers to Office Graph workflow behavior.
- [x] 4.2 Ensure operator workflow projections provide command identity, affordance state, blocker reasons, safe explanations, required fields, target ids, and optional trace or decision links when authorized.
- [x] 4.3 Add tests that disabled, hidden, and redacted command affordances render without leaking policy-sensitive details.

## 5. Verification

- [x] 5.1 Add or update frontend typecheck and component tests for the route-first operator module.
- [x] 5.2 Add the Relay compiler check to frontend verification.
- [x] 5.3 Add import-boundary tests that prevent shared UI from importing route internals, GraphQL documents, product command logic, or domain-specific product vocabulary.
- [x] 5.4 Keep or update Phoenix app-shell asset tests so `/operator` fails when the built React Router assets are missing.
- [x] 5.5 Run the project Nix-shell verification commands for OpenSpec, frontend tests, backend tests affected by the app shell, and formatting.
