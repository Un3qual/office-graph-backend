## 1. Route-Aware Product Shell And Navigation

- [x] 1.1 Make the shared shell navigation route-aware while preserving the operator route.
  - First extend `assets/src/ui/primitives.test.tsx` with a `MemoryRouter`
    case proving implemented destinations are links, the current destination
    receives current-page semantics, and unavailable destinations stay disabled;
    run `pnpm exec vitest run src/ui/primitives.test.tsx` from `assets` and
    confirm the new assertions fail against the button-only navigation.
  - Modify `assets/src/ui/NavRail.tsx` to accept generic destination
    descriptors and use `NavLink` only for implemented destinations. Create a
    shallow generic `assets/src/ui/WorkspaceShell.tsx` for the repeated brand,
    navigation, header, and content frame, then adapt
    `assets/app/routes/operator/components/OperatorLayout.tsx` without moving
    operator behavior into shared UI.
  - Update `assets/src/ui/importBoundaries.test.ts` only as needed to prove the
    new shared shell remains free of route-module, Relay, and product-vocabulary
    dependencies.
  - Run `pnpm exec vitest run src/ui/primitives.test.tsx
    src/ui/importBoundaries.test.ts app/routes/operator/route.test.tsx` and
    confirm the navigation and existing operator tests pass.
  - Commit this independently testable slice as `feat: add route-aware product
    navigation`.

## 2. Route-Owned Relay Packet Data

- [x] 2.1 Add the packet route's Relay documents, generated types, and route-local query state.
  - Create failing tests under `assets/app/routes/packets/` that import the
    packet query through the Vite Relay transform, enforce route ownership, and
    exercise connection mapping for empty, populated, next-page, and
    previous-page data; run the focused Vitest files and confirm they fail
    because the route data boundary does not exist.
  - Create `assets/app/routes/packets/data.ts`, `types.ts`, and `workflow.ts`.
    Define `PacketsRouteQuery(first, after)`, an inline packet fragment, a
    route-local `usePacketsWorkflow` hook using the existing Relay environment,
    cursor history, observable cleanup, safe error normalization, and local
    selection semantics from the approved design.
  - Run `pnpm run relay` to generate the packet artifacts, then run
    `pnpm exec vitest run app/routes/packets/data.test.ts
    app/routes/packets/workflow.test.ts app/routes/packets/architecture.test.ts`
    and `pnpm run typecheck`.
  - Commit this independently testable slice as `feat: add packet Relay data
    boundary`.

## 3. Packet Workspace Route And Verification

- [ ] 3.1 Build, register, and verify the `/packets` workspace end to end.
  - Add a failing `assets/app/routes/packets/route.test.tsx` covering loading,
    empty, safe error, default selection, row selection, selected packet
    summary, next-page, and previous-page behavior; add a failing Phoenix
    controller test proving `/packets` serves the React Router app shell.
  - Create the route-owned packet workspace and focused list/detail/layout
    components under `assets/app/routes/packets/`, register the route in
    `assets/app/routes.ts`, provide `/operator` and `/packets` destinations from
    route-owned layouts, and add the minimal existing-system CSS needed for a
    dense list/detail workspace without Tailwind or new dependencies.
  - Add `get "/packets", OperatorConsoleController, :index` to
    `lib/office_graph_web/router.ex` and update app-shell verification so both
    product routes fail safely when built assets are missing.
  - Run `pnpm run verify` from `assets`, focused Phoenix app-shell tests, strict
    OpenSpec validation for `add-packets-route`, and the project Nix-shell
    `mix verify` gate. Confirm the Relay compiler, typecheck, import boundaries,
    component tests, production build, app-shell checks, backend tests, static
    analysis, and formatting all pass.
  - Commit the completed route as `feat: add packet workspace route`.
