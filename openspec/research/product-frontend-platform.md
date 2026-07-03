# Product Frontend Platform Research

Status: discussion artifact, not an accepted OpenSpec change.

This document consolidates the frontend architecture research from the operator
console reset discussion. It is intentionally not a proposal, spec delta, or
implementation plan yet. The goal is to give us a stable document to discuss,
challenge, split apart, and later promote into OpenSpec artifacts once the
decisions are solid.

## Why This Exists

The first operator console proved that Phoenix can serve a React product UI
backed by Office Graph projections. It also pulled the frontend toward
an operator-demo shape: one route, one product screen, one workbench vocabulary,
and architecture choices made in service of getting the first screen visible.

That is not enough for the product we are building. Office Graph needs a large,
dense, enterprise React frontend that can grow across inboxes, work packets,
runs, evidence, verification, authorization, audit, integrations, agent runtime,
settings, and future department-specific workflows without turning every screen
into a special case.

The architecture problem is not primarily styling. The problem is ownership:
routes, feature modules, projections, server state, URL state, local state,
allowed actions, realtime invalidation, shared UI boundaries,
accessibility, testing, and query optimization all need explicit conventions
before the second and third product screens copy whatever `/operator` happens
to look like.

## Research Inputs

This document combines four parallel research tracks:

- Repo and OpenSpec constraints: what Office Graph has already decided, where
  the current frontend conflicts with the product direction, and what should be
  captured next.
- Enterprise React architecture: route ownership, app shell, module boundaries,
  server state, URL state, code splitting, and router options.
- Data, GraphQL, realtime, and authorization: projection ownership, generated
  operation types, TanStack Query cache discipline, Phoenix channel invalidation
  semantics, and policy-aware UI behavior.
- Design system, component taxonomy, testing, and enforcement: shared
  primitives, React Aria, accessibility gates, import boundaries, and
  verification strategy.

Relevant existing Office Graph artifacts:

- `openspec/project.md`
- `openspec/project-plan.md`
- `openspec/specs/frontend-architecture/spec.md`
- `openspec/specs/ui-projection-contracts/spec.md`
- `openspec/specs/realtime-delivery/spec.md`
- `openspec/specs/authorization-governance/spec.md`
- `openspec/specs/ash-api-surface/spec.md`
- `openspec/changes/archive/2026-07-02-rebuild-operator-frontend-foundation/design.md`
- `openspec/changes/archive/2026-07-02-reduce-operator-query-load/design.md`

External references:

- React Router route modules:
  https://reactrouter.com/start/framework/route-module
- React Router data routing:
  https://reactrouter.com/start/data/routing
- React Router error boundaries:
  https://reactrouter.com/how-to/error-boundary
- TanStack Query query keys:
  https://tanstack.com/query/latest/docs/framework/react/guides/query-keys
- TanStack Query defaults:
  https://tanstack.com/query/latest/docs/framework/react/guides/important-defaults
- TanStack Query invalidation:
  https://tanstack.com/query/latest/docs/framework/react/guides/query-invalidation
- TanStack Query request waterfalls:
  https://tanstack.com/query/latest/docs/framework/react/guides/request-waterfalls
- TanStack Query prefetching:
  https://tanstack.com/query/latest/docs/framework/react/guides/prefetching
- GraphQL Code Generator React Query guide:
  https://the-guild.dev/graphql/codegen/docs/guides/react-query
- React Suspense:
  https://react.dev/reference/react/Suspense
- React lazy:
  https://react.dev/reference/react/lazy
- Vite features:
  https://vite.dev/guide/features.html

## Existing Locked Constraints

Office Graph has already made several decisions that should constrain the
frontend platform:

- React is the product UI.
- Phoenix remains the app-shell and API host.
- Phoenix LiveView is forbidden for product UI.
- Tailwind CSS is forbidden for product UI, prototypes, examples, generated
  code, design-system work, and temporary scaffolding. Tailwind-dependent
  component libraries and Tailwind utility-class conventions are not candidates
  for this project.
- OpenSpec is the workflow source of truth.
- GraphQL and JSON API both exist, but product frontend reads should normally
  use GraphQL projections.
- JSON API remains valuable for integration, compatibility, and customer API
  endpoints; it should not automatically define product frontend architecture.
- Authorization is core product architecture, not a late controller concern.
- Product UI must read through authorization-filtered projection
  contracts rather than ad hoc controller or resolver reads.
- Backend projections should provide allowed commands, allowed actions,
  blockers, and safe explanations; the UI should not reconstruct domain meaning
  from raw graph links or private resource state.
- Realtime payloads are projection invalidation, patch, stale, or refetch
  hints. They are not durable frontend truth.
- The current product spine should stay product-oriented:

```text
Signal
  -> Work Item
  -> Work Packet
  -> Run
  -> Check
  -> Evidence
  -> Verification
```

Infrastructure vocabulary such as graph IDs, operation IDs, actor IDs,
watermarks, audit traces, raw archives, policy bundles, and internal replay
identity should live behind trace, debug, audit, or admin surfaces unless the
workflow explicitly needs them.

## Current Frontend Risk

The current operator reset is better than the original demo because it has
GraphQL-only frontend hooks, TanStack Query, query keys, mappers, view models,
focused panels, and an architecture test blocking the old JSON adapter.

The remaining risk is different: the first route can still become the whole app
architecture by accident.

Observed risks:

- `App` still mounts only the operator route.
- `main.tsx` still mounts only an operator-console root.
- Vite still emits under an operator-oriented asset path.
- Phoenix still serves a fixed `/operator` shell.
- Navigation currently includes static unavailable items rather than a product
  route model.
- Search and other shell concepts are not yet backed by product decisions.
- Some panels still expose infrastructure vocabulary by default.
- The active specs have a migration tension: the rebuild direction removed
  frontend JSON adapters, while the query-load work preserved backend JSON
  behavior for current callers.

The correct next move is not more operator polish. The correct next move is a
frontend platform design change that decides how future product screens are
owned, loaded, queried, invalidated, authorized, rendered, tested, and kept
fast.

## Recommended Architecture Direction

Adopt a modular-monolith React SPA:

- Phoenix serves the HTML shell and static assets.
- React owns product UI.
- A client data router owns navigation and route-level loading/error handling.
- Feature modules own their product routes, projection operations, query keys,
  mapping, typed UI data, components, and tests.
- TanStack Query remains the only server-state cache.
- URL state owns deep-linkable product state.
- Local React state owns ephemeral control state.
- Shared UI remains generic and boring.

Target directory shape:

```text
assets/src/
  app/
    App.tsx
    AppShell.tsx
    routes.tsx
    providers.tsx
  platform/
    graphql/
    query/
    auth/
    realtime/
    telemetry/
    env/
  shared/
    design/
    ui/
    a11y/
    testing/
    utils/
  domains/
    work/
    runs/
    evidence/
    verification/
    identity/
    audit/
  features/
    operator/
    inbox/
    work-packets/
    runs/
    evidence/
    verification/
    integrations/
    identity/
    audit/
    graph/
    agent-runtime/
    settings/
```

The exact folder names can change. The important rule is ownership:

- `app/` composes the shell, providers, and route tree.
- `platform/` owns infrastructure clients and adapters.
- `shared/` owns generic primitives and utilities only.
- `domains/` owns stable cross-feature product concepts when a concept is truly
  shared.
- `features/*` owns product-screen behavior.

## Route Ownership And Router Decision

The frontend should choose a real route framework before adding the next
product route. A manual single-route shell will not scale.

Leading recommendation: React Router Data Mode plus TanStack Query.

Why it fits:

- Mature nested route model.
- Route-level loaders and actions.
- Route error boundaries.
- Familiar app-shell composition.
- Does not require Next.js or SSR.
- Works with a Phoenix-served SPA.
- Lets loaders prime TanStack Query instead of creating a competing cache.

Alternative: TanStack Router plus TanStack Query.

Why it may fit:

- Strong typed route/search-param model.
- Good if URL state and route contracts become especially central.
- More architectural commitment and less conservative than React Router.

Rejected default: manual app shell with query hooks only.

Why it should not be the long-term default:

- Delays route ownership decisions.
- Delays nested error/loading conventions.
- Delays URL state rules.
- Delays code splitting.
- Lets the first screen define the whole app.

Open discussion:

- Is URL/search-param type safety important enough to justify TanStack Router
  now?
- Should the first formal change pick React Router, or should the change first
  define route ownership contracts and leave the library decision as a short
  spike?
- How much Phoenix route/controller structure should mirror the React route
  tree?

## Feature Module Contract

A feature module should own:

- Route registration or route module.
- GraphQL documents for that feature.
- Query key factories.
- Query option factories and hooks.
- Mutation hooks and allowed-action handling.
- Projection mappers from GraphQL results to typed UI data.
- Derived state helpers.
- Feature-specific components.
- Feature-specific fixtures and tests.
- Realtime invalidation subscriptions for its projections.

A feature module should not:

- Export raw GraphQL response objects to components.
- Let components call `fetch` directly.
- Let components build domain command inputs by walking graph links.
- Hide durable workflow state in local component state.
- Put domain-specific UI in shared primitives.
- Expose infrastructure vocabulary as the default product language.

Example feature layout:

```text
assets/src/features/work-packets/
  route.tsx
  routes.ts
  packetGraphql.ts
  packetQueries.ts
  packetMutations.ts
  packetMappers.ts
  packetViewModels.ts
  packetDerived.ts
  realtime.ts
  components/
    PacketWorkbench.tsx
    PacketHeader.tsx
    PacketReadinessPanel.tsx
    PacketContextPanel.tsx
  __tests__/
```

## State Model

Use four state categories:

| State category | Owner | Examples |
| --- | --- | --- |
| Server state | TanStack Query over GraphQL projections | inbox rows, packet readiness, run state, verification state, audit history |
| URL state | Router/search params/path params | selected item id, tab, filters, sort, pagination, deep-linked workspace context |
| Local UI state | React component state | open panel, hover, focus, transient selection, unsaved form draft |
| Cross-route client state | Small explicit store only if needed | active workspace/session, feature flags, command palette, client-only workflow state |

Rules:

- Do not use Redux or Zustand for server state.
- Do not put deep-linkable state only in local component state.
- Do not put sensitive data in query keys or URL state.
- Do not let realtime become a parallel client store.
- Add a global client store only when multiple routes need client-only state
  that cannot be represented in server state or the URL.

## GraphQL Operation Strategy

Use feature-owned operations, not component-scattered operations.

Recommended progression:

1. Keep GraphQL documents in feature data modules.
2. Give every operation a stable name.
3. Generate operation result and variable types.
4. Map generated operation types into product view models.
5. Add an operation registry for CI.
6. Add persisted queries for production hardening.

Components should never consume GraphQL response objects directly. They should
consume product view models.

Fragments should initially be owned by projection/data modules, not arbitrary
presentational components. Relay-style fragment colocation can be reconsidered
later if component ownership and data dependencies become painful.

Mutation contracts should be command-shaped:

- Single `input`.
- Idempotency or operation context where relevant.
- Stable `extensions.code` errors.
- Returned affected projection identities.
- Returned watermarks or projection versions where relevant.
- Returned invalidation hints so the frontend does not infer cache work from
  raw graph links.

Open discussion:

- Do we introduce GraphQL Code Generator in the frontend platform change, or
  stage it after route/module boundaries land?
- Do we require persisted queries immediately, or first require operation names
  and operation ownership?
- Should frontend feature modules own fragments, or should backend projection
  modules define canonical operation shapes?

## TanStack Query Strategy

TanStack Query should be the only server-state cache.

Query keys should be factory-owned and structured. A safe enterprise taxonomy:

```text
[area, projection, tenantScope, policyScopeVersion, variablesShape]
```

Rules:

- Query keys must include variables used by the query function.
- Query keys must include enough tenant/workspace/policy context to prevent
  cross-identity or cross-policy leakage.
- Query keys must not include sensitive raw content.
- Query functions should accept and pass through TanStack Query's `AbortSignal`.
- Stale/refetch settings should be projection-class defaults, not ad hoc per
  component magic.

Suggested projection-class defaults:

| Projection class | Stale behavior | Refetch behavior |
| --- | --- | --- |
| Inbox/workflow active state | short stale time | refetch on reconnect/focus where useful |
| Packet readiness/run state | short stale time | invalidate on command and realtime hint |
| Audit/history | longer stale time | refetch on explicit navigation or relevant hint |
| Authorization/policy facts | aggressive invalidation | purge or mark stale on policy/fact version changes |
| Static configuration | long stale or static | invalidate only on explicit version change |

Optimistic updates should be rare for governed workflow state. They are
acceptable for reversible presentation state or command-pending markers. For
policy-sensitive mutations, prefer server-confirmed updates plus returned
invalidation hints.

## Realtime Strategy

Phoenix channel events should become cache reconciliation hints, not a second
state model.

Realtime event contract should include:

- Projection name.
- Affected ids.
- Operation id when relevant.
- Watermark or projection version.
- Policy fact version when relevant.
- Reconciliation kind:
  - `invalidate`
  - `patch-safe-fields`
  - `remove`
  - `mark-stale`
  - `reauthorize`

Default behavior should be `queryClient.invalidateQueries` using projection key
factories.

Use `setQueryData` only when the event contract explicitly says:

- The payload is safe for the subscriber.
- The payload is authorized for the current policy context.
- The payload version is compatible with the cached projection.
- The patch cannot leak restricted fields.

On reconnect, missed sequence, or policy/fact-version mismatch, refetch the
authoritative GraphQL projection.

## Authorization-Aware UI

The UI should render capabilities exactly as backend projections describe them.
It should not infer capability from status strings, role names, graph
relationships, resource types, or private state.

Allowed action fields:

```text
action
state: enabled | disabled | hidden | redacted
reasonCode
safeExplanation
requiredFields
targetIds
traceId or decisionId when authorized
```

Rules:

- Show disabled actions when the workflow makes the action expected and the
  explanation is safe.
- Hide actions when revealing them leaks capability, resource existence, or
  sensitive policy structure.
- Redacted resources should render safe placeholders and reason codes.
- Raw policy internals stay server-side.
- Trace and decision links appear only when policy allows that visibility.

This needs to be a frontend architecture concern from the start, not a later
design-system flourish.

## Shared UI And Design System Taxonomy

Use a strict taxonomy:

```text
design tokens
  -> shared primitives
  -> shared compounds
  -> feature components
  -> workflow-specific components
```

Recommended directories:

```text
assets/src/shared/design/
assets/src/shared/ui/
assets/src/features/<feature>/components/
```

If the project keeps `assets/src/design` and `assets/src/ui` at top level, the
same rules still apply.

Layer rules:

- Design tokens contain semantic color, spacing, typography, density, z-index,
  focus ring, motion, and layout tokens. No React. No product nouns.
- Shared primitives wrap accessible generic controls: button, field, dialog,
  tabs, list, table shell, menu, tooltip, split pane, toolbar, empty state.
- Shared compounds compose primitives into generic enterprise patterns:
  workbench shell, nav rail, pane header, inspector panel, list row shell.
- Feature components know product concepts: packets, runs, evidence,
  verification, audit traces, graph relationships, integration settings.
- Workflow-specific components stay inside their owning feature.

Shared UI props should say `tone`, `density`, `selectionMode`, `ariaLabel`, and
`state`. They should not say `runStatus`, `packetReadiness`,
`verificationResult`, `graphType`, or `policyBundle`.

React Aria Components are the recommended default for shared interactive
pieces. Exceptions should be deliberate and documented.

Accessibility baseline:

- Accessible role and name in tests.
- Keyboard navigation for lists, tables, tabs, menus, and dialogs.
- Focus restoration after dialogs and commands.
- Visible focus rings.
- Escape dismissal where appropriate.
- Non-color-only status cues.
- Disabled controls with safe explanations where appropriate.

## Testing And Enforcement

Testing should be layered:

- Token tests for semantic token availability and CSS/TypeScript consumption.
- Shared primitive tests for role/name/keyboard behavior.
- Feature mapper and derived-state tests.
- Query hook tests with a fresh `QueryClient`.
- Route component tests with router context and operation-aware mocks.
- Import-boundary tests.
- App-shell asset verification.
- Browser smoke tests for built routes.
- Query-count and N+1 regression tests for projection-backed pages.

Start with Vitest import-boundary tests because the repo does not currently
have a mature frontend ESLint boundary setup. Add ESLint later with
`no-restricted-imports` or equivalent rules matching the tested policy.

Boundary rules to enforce:

- `shared/design` imports no product-specific modules.
- `shared/ui` imports no feature modules, query hooks, GraphQL documents, or
  domain-specific product vocabulary.
- `features/*` can import `shared/*`.
- `features/*` should not import sibling feature internals unless there is an
  accepted domain/shared boundary.
- Route modules do not contain raw GraphQL documents, raw `fetch` calls, or
  response mapping logic.
- Product components do not import JSON API clients unless a temporary
  exception exists with a retirement condition.

Browser smoke should come after the platform skeleton is real enough to run:

- Phoenix shell loads generated assets.
- First route renders.
- Keyboard selection works.
- Dialog or command focus behavior works.
- No console errors on first render.

Do not add broad visual regression too early. Add it when shared compounds are
stable enough that snapshots protect real contract instead of freezing churn.

## Query Optimization And N+1 Discipline

Query optimization must be part of the frontend platform, not a backend cleanup
after screens feel slow.

Frontend architecture should require:

- Feature-owned GraphQL operations.
- Named operations.
- Query-shape review for every new product route.
- Operation registry or persisted-query registry before production hardening.
- Owner tags for operations.
- Projection contract tests that exercise expected data shape.
- Query-count regression tests for backend projection reads.
- Explicit pagination/filtering/sorting contracts.
- Route-level prefetching or parent composition to avoid request waterfalls.
- Realtime invalidation tests that prove events do not trigger unbounded
  refetch storms.
- Architecture docs that call out likely N+1 paths before implementation.

Every new projection-backed route should answer:

- What backend records does this route need?
- Which projection owns the read shape?
- What is the expected query count for the first render?
- What is the expected query count after selecting a row?
- What is the expected query count after a realtime update?
- What pagination limits or cursor rules prevent unbounded reads?
- Which relationships are preloaded server-side?
- Which fields are safe to cache across policy contexts?
- Which events invalidate or refetch the route?

This should be encoded in OpenSpec and verification gates, not left as a code
review preference.

## Performance Model

Performance rules:

- Lazy-load by product route, not by every component.
- Keep the global app shell and nav free of heavy feature imports.
- Use route loaders or route-level prefetch to flatten request waterfalls.
- Let Vite handle dynamic import chunks, CSS code splitting, and modulepreload
  optimization before adding manual chunk tuning.
- Use React `lazy` and `Suspense` at route boundaries.
- Do not use Suspense as an arbitrary data-fetching strategy until the router
  and query patterns explicitly support it.
- Use virtualization only when list/table sizes require it.
- Do not build a mega data-grid abstraction before real table requirements are
  known.

Performance gates should begin with route smoke, bundle awareness, query-count
tests, and waterfall review. Manual chunk tuning can wait for evidence.

## Product Vocabulary Rule

Default product UI should use product-spine vocabulary:

- work item
- packet
- run
- check
- evidence
- decision
- blocker
- readiness
- verification
- approval
- trace

Infrastructure vocabulary should move into trace/debug/audit panels:

- graph id
- operation id
- actor id
- raw archive
- watermark
- replay identity
- policy bundle
- revision pointer
- source sequence

This matters architecturally because naming affects module boundaries,
projection fields, UI component names, tests, and what future contributors copy.

## OpenSpec Change To Create

Suggested change id:

```text
design-product-frontend-platform
```

The change should be design-first. It should not implement the router, codegen,
or new screens in the same step.

Candidate artifacts:

- `proposal.md`: scope the platform architecture work and explicitly state that
  implementation follows later.
- `design.md`: record route ownership, app shell, feature modules, state model,
  GraphQL/TanStack Query/realtime rules, authorization UI, design-system layers,
  testing, query optimization, and deferred decisions.
- `tasks.md`: likely only design and validation tasks until we choose to
  execute.
- `specs/frontend-architecture/spec.md`: add durable requirements for route
  ownership, module boundaries, shared UI purity, router adoption, state model,
  and verification gates.
- `specs/ui-projection-contracts/spec.md`: add projection-design templates,
  allowed-action model, realtime reconciliation, and frontend redaction UX.
- `specs/ash-api-surface/spec.md`: clarify product frontend GraphQL vs JSON
  API integration rules.

Potential requirement names:

- Frontend Route Ownership
- Modular Feature Boundaries
- Shared UI Purity
- Server URL And Local State Separation
- GraphQL Operation Ownership
- Query Key And Cache Scope Discipline
- Realtime Projection Reconciliation
- Authorization Affordance Rendering
- Query Optimization And N+1 Gates
- Dense Enterprise Accessibility Baseline
- Product Vocabulary Separation

## Decisions To Discuss

1. Router choice:
   - React Router Data Mode now.
   - TanStack Router now.
   - Short router spike before locking.

2. GraphQL typing:
   - Introduce GraphQL Code Generator in the platform change.
   - Require operation names/ownership first, then codegen in a follow-up.

3. Persisted queries:
   - Require immediately for all product frontend operations.
   - Stage after operation registry and query-shape review.

4. JSON bridge policy:
   - Product frontend never imports JSON adapters.
   - Temporary frontend JSON adapters require an explicit exception and
     retirement condition.
   - Backend JSON compatibility remains separate from product frontend needs.

5. URL state:
   - Move selected operator item, tabs, filters, and pagination into URL now.
   - Wait until the router change establishes route/search conventions.

6. Shared UI structure:
   - Keep current top-level `assets/src/design` and `assets/src/ui`.
   - Move toward `assets/src/shared/design` and `assets/src/shared/ui`.

7. React Aria:
   - Make it the default for shared interactive components.
   - Use it selectively while documenting accessibility contracts manually.

8. Realtime scope:
   - Define event contracts in the platform change.
   - Defer detailed Phoenix channel implementation until a realtime screen
     needs it.

9. Operator reset status:
   - Keep the current reset as a provisional implementation.
   - Revert the reset and return to research-only.
   - Keep it but immediately supersede it with the frontend platform OpenSpec.

## What Not To Decide Yet

Do not decide these in the first platform design unless a requirement forces
the issue:

- Micro-frontends or module federation.
- Next.js or SSR.
- Tailwind CSS or Tailwind-dependent UI libraries.
- Full graph canvas behavior.
- Workflow builder UI.
- Rich text editor architecture.
- Full department-specific navigation.
- Broad mobile UI.
- A generic enterprise data-grid abstraction.
- A polished Storybook or full visual-regression suite.
- Manual Vite chunk tuning.
- A global client store beyond minimal shell/session needs.

## Anti-Patterns To Avoid

- Letting `/operator` define the whole app shell.
- Creating `shared` components with workflow nouns.
- Passing raw GraphQL response objects into components.
- Calling `fetch` directly in product components.
- Keeping server state in local React state or global client stores.
- Treating realtime payloads as durable frontend truth.
- Inferring authorization from status strings or role names.
- Building command inputs from raw graph links.
- Hiding query-count expectations until performance work.
- Creating a mega grid/table abstraction before real requirements exist.
- Freezing visual design before module ownership and accessibility are clear.

## Working Recommendation

Create `design-product-frontend-platform` as the next OpenSpec change and use
this document as the discussion source for that change.

The most likely accepted direction is:

- Phoenix-served React SPA.
- React Router Data Mode plus TanStack Query.
- Feature-owned route modules and typed data hooks.
- Generated GraphQL operation types after operation ownership is locked.
- No product frontend JSON adapters without explicit temporary exceptions.
- Realtime as projection invalidation/patch/refetch hints.
- Allowed actions supplied by backend projections.
- Strict shared UI purity and React Aria-based accessibility baseline.
- Query optimization and N+1 gates as required route/projection verification.

The document should remain editable until the OpenSpec proposal and spec deltas
are accepted.
