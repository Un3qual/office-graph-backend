## 1. GraphQL Client Decision

- [x] 1.1 Record Relay as the selected product GraphQL client model in the implementation notes.
- [x] 1.2 Remove TanStack Query plus generated GraphQL operation types from the product GraphQL implementation scope.
- [ ] 1.3 Verify the current Absinthe/AshGraphql schema supports Relay object identity, connection-compatible pagination, fragments, generated TypeScript, mutation payloads, and test ergonomics before route migration depends on it.

## 2. React Router Framework Mode Foundation

- [ ] 2.1 Add React Router Framework Mode configuration under `assets` without changing Phoenix product routing semantics beyond serving the built SPA.
- [ ] 2.2 Create the route root, route config, and route-owned operator module using the accepted route-first layout.
- [ ] 2.3 Add `AppProviders.tsx` for React application wrappers only, including the Relay provider and any required app/session context.
- [ ] 2.4 Keep shared UI shallow under the accepted layout and avoid `platform`, `domains`, `shared/design`, or `shared/ui` folders unless a concrete repeated-code need is documented.

## 3. Operator Route Migration

- [ ] 3.1 Move the existing `/operator` React surface into the route-owned module without adding new product behavior.
- [ ] 3.2 Replace old operator data hooks or mappers with Relay root queries, fragments, and generated Relay types.
- [ ] 3.3 Remove frontend JSON adapter assumptions for operator workflow reads once GraphQL route data covers the current behavior.
- [ ] 3.4 Preserve current operator loading, empty, error, selected-row, readiness, run, and verification states.

## 4. Command Affordance Contract

- [ ] 4.1 Rename frontend planning and implementation language from generic "actions" to product commands and UI affordances where it refers to Office Graph workflow behavior.
- [ ] 4.2 Ensure operator workflow projections provide command identity, affordance state, blocker reasons, safe explanations, required fields, target ids, and optional trace or decision links when authorized.
- [ ] 4.3 Add tests that disabled, hidden, and redacted command affordances render without leaking policy-sensitive details.

## 5. Verification

- [ ] 5.1 Add or update frontend typecheck and component tests for the route-first operator module.
- [ ] 5.2 Add the Relay compiler check to frontend verification.
- [ ] 5.3 Add import-boundary tests that prevent shared UI from importing route internals, GraphQL documents, product command logic, or domain-specific product vocabulary.
- [ ] 5.4 Keep or update Phoenix app-shell asset tests so `/operator` fails when the built React Router assets are missing.
- [ ] 5.5 Run the project Nix-shell verification commands for OpenSpec, frontend tests, backend tests affected by the app shell, and formatting.
