## Context

Office Graph has one Phoenix-served React operator console. That proved the
basic product UI path, but the current frontend should not define every future
screen by accident. The next product screens need a shared route, GraphQL,
state, command-affordance, and test posture before implementation starts.

Current constraints:

- React is the product UI stack.
- Phoenix LiveView is forbidden for product UI.
- Tailwind and Tailwind-dependent component libraries are forbidden.
- Product frontend reads should use GraphQL, while JSON API remains required
  for integrations and external API use.
- The frontend should stay dense, operational, and route-first rather than
  marketing-oriented or over-abstracted.

References checked while preparing this design:

- React Router Framework Mode routing uses `app/routes.ts` for route
  configuration and route modules for route behavior.
- Relay is a GraphQL client for React with fragments, generated types,
  pagination support, preloaded queries, and a normalized store.

## Goals / Non-Goals

**Goals:**

- Lock React Router Framework Mode as the frontend route architecture.
- Keep the first platform layout conventional, route-first, and shallow.
- Require a serious Relay decision before implementation, compared against
  TanStack Query plus generated GraphQL operation types.
- Use one GraphQL server-state cache/client model for product GraphQL data.
- Make backend-provided commands and UI affordances explicit, including hidden,
  disabled, redacted, and safe-explanation states.
- Define concrete verification gates that match the project today.

**Non-Goals:**

- Do not implement React Router Framework Mode in this design change.
- Do not add Relay, TanStack Query changes, GraphQL Code Generator, or new
  package dependencies in this design change.
- Do not add new product screens.
- Do not introduce SSR, RSC, Next.js, micro-frontends, module federation,
  Tailwind, shadcn, a generic data-grid framework, or broad visual regression.
- Do not create `platform`, `domains`, `shared/design`, or `shared/ui` folders
  before repeated real code proves they are needed.

## Decisions

### 1. Use React Router Framework Mode

Office Graph should use React Router Framework Mode for the product frontend.
Framework Mode gives the project explicit route modules, root route structure,
route configuration, route-level error boundaries, pending states, loaders,
actions when needed, and build conventions. It is a better fit than continuing
with a hand-composed single-route shell.

The implementation should run as a Phoenix-served SPA unless a later accepted
change explicitly adds SSR. The first step is adopting the framework route
shape, not changing the backend deployment model.

Rejected defaults:

- Manual route shell with query hooks only: too easy for `/operator` to become
  the whole app architecture.
- TanStack Router now: useful type-safety story, but less conservative for this
  Phoenix-served app and not needed before React Router Framework Mode has been
  tried.
- Next.js or SSR: outside current project direction.

### 2. Use a route-first, shallow file layout

The frontend layout should follow React Router Framework Mode first and add
deeper abstractions only after real screens repeat.

Target shape:

```text
assets/
  react-router.config.ts
  app/
    root.tsx
    routes.ts
    AppProviders.tsx

    routes/
      operator/
        route.tsx
        components/
        data.ts
        types.ts
        tests/

    relay/              # only if Relay is selected
      environment.ts
      fetchGraphQL.ts

    graphql/            # only if TanStack Query + codegen is selected
      fetchGraphQL.ts
      generated/

    ui/
      Badge.tsx
      Button.tsx
      Panel.tsx

    styles/
      global.css
```

Rules:

- Routes are the main ownership boundary.
- Route-specific code stays under the route folder.
- Shared UI remains shallow and product-vocabulary-free.
- `AppProviders.tsx` means React app wrappers such as Relay environment,
  router integration, session/app context, feature flags, or app config. It
  does not mean external integration provider adapters.
- Avoid `viewModels.ts` and MVVM-style vocabulary. If Relay is selected, use
  fragments and generated Relay types. If TanStack Query plus codegen is
  selected, use `types.ts`, `data.ts`, and small mapping helpers only where
  needed.
- Do not introduce `platform` or `domains` folders until at least two product
  routes prove a real shared boundary that cannot stay in route folders or
  shallow `ui`.

### 3. Decide Relay before implementation

Relay must be evaluated as a first-class option, not an afterthought. Office
Graph is graph-shaped, GraphQL-first, authorization-sensitive, and likely to
need stable object identity, pagination, fragment ownership, and normalized
updates. Those are Relay strengths.

The implementation decision should be one of:

1. React Router Framework Mode plus Relay.
2. React Router Framework Mode plus TanStack Query and generated GraphQL
   operation types.

The project must not use both Relay and TanStack Query as competing caches for
the same product GraphQL data. It is acceptable to keep TanStack Query later
for non-GraphQL or non-product server state only if a real need appears.

Decision criteria:

- GraphQL schema compatibility with Relay object identity and connections.
- Authorization and redaction behavior.
- Pagination and realtime invalidation/update behavior.
- Generated TypeScript quality.
- Testing ergonomics.
- Amount of custom glue code required.
- Fit with React Router Framework Mode route loaders and route modules.

### 4. Use commands and affordances, not generic frontend "actions"

The earlier planning language overused "actions". That collides with React
Router actions and is too vague.

Use:

- **Command** for a product operation such as prepare packet, start run, accept
  evidence, apply proposed changes, or verify completion.
- **Affordance** for what the UI is allowed to show: enabled command, disabled
  command, hidden command, redacted target, navigation target, safe
  explanation, required fields, blocker reasons, or trace link.

Backend projections should provide these affordances. The frontend should not
infer them from role names, raw status strings, graph relationship names, or
private policy state.

### 5. Keep shared UI generic without over-specifying props

The important rule is not the exact prop names. The rule is that shared UI
components must not understand product concepts.

Good:

- A generic `Badge` accepts presentation and accessibility props.
- A route maps `packet readiness = blocked` into the appropriate badge tone.

Bad:

- A generic `Badge` accepts `packetReadiness`.
- A generic `Panel` accepts `policyBundle`.
- A shared table shell knows about runs, packets, evidence, or graph types.

### 6. Keep testing concrete

The first platform gates should be tests and commands the repo can actually
run:

- TypeScript typecheck.
- Component tests for shared UI and route components.
- Route smoke tests for built routes.
- Relay compiler or GraphQL codegen check, depending on the selected client.
- Import-boundary tests for route/shared UI separation.
- Phoenix app-shell asset test.
- Focused backend query-count tests only for projection reads that can grow by
  rows, graph links, runs, evidence, or integration records.

Do not add broad visual regression, token-package tests, or a full enterprise
data-grid test harness until implementation creates concrete contracts worth
protecting.

## Risks / Trade-offs

- **Relay may force schema work** -> Evaluate Relay against current Absinthe and
  AshGraphql output before implementation commits to it.
- **Route-first folders can duplicate small helpers early** -> Prefer a little
  duplication until two real routes prove the correct shared boundary.
- **React Router Framework Mode may require build integration changes** ->
  Keep the first implementation small and verify Phoenix app-shell asset output
  before moving more screens.
- **TanStack Query remains familiar from the current operator reset** ->
  Familiarity is not enough; choose it only if it beats Relay for this product
  after the explicit comparison.
- **Authorization affordance contracts can grow large** -> Keep first fields to
  command identity, state, safe explanation, required fields, target ids, and
  optional trace or decision link when authorized.

## Migration Plan

1. Finalize this design and spec delta.
2. Decide Relay vs TanStack Query plus generated GraphQL operation types before
   implementation begins.
3. Implement React Router Framework Mode in the smallest Phoenix-served SPA
   slice that keeps `/operator` working.
4. Move operator route ownership under the route-first layout.
5. Replace old frontend JSON adapter assumptions with the selected GraphQL
   client model.
6. Add only the concrete verification gates needed for the selected client and
   route layout.
7. Defer additional product routes until the route-first foundation passes its
   verification gate.

Rollback for implementation should be straightforward: keep the existing
Phoenix `/operator` shell available until the Framework Mode build and asset
verification pass.

## Open Questions

- Does current Absinthe/AshGraphql output satisfy Relay's object identity and
  connection expectations, or is a small schema adjustment needed?
- Should generated GraphQL artifacts live under `assets/app/relay/` or a
  generated folder outside `app/` to keep route source cleaner?
- Which first command affordance fields are enough for `/operator` without
  over-modeling future workflows?
- Should URL state for selected operator row and tab move into React Router
  search params in the first implementation, or wait for the second route?
