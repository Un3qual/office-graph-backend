# Relay Suspense Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the packet and operator routes' hand-written Relay subscription state machines with Relay render-time hooks under explicit Suspense and safe error boundaries, while preserving the approved page-replacing pagination and operator-panel behavior.

**Architecture:** A product-neutral `AsyncBoundary` owns only React suspension, safe fallback rendering, and reset-key recovery. Route shells retain local cursor history and requested selection; query children call `useLazyLoadQuery` with `network-only`, map generated Relay data into lean route models, and render loaded workspaces. Operator readiness validation and run-state reads live in selection-keyed inspector children so their loading or failure replaces only the affected panel, not the inbox or selected-item context.

**Tech Stack:** React 19, TypeScript, React Router 8, Relay 21, Vitest, Testing Library, StyleX/CSS, OpenSpec, Nix, Elixir/Mix verification.

> **Archive status:** Completed. Checked RED steps record the intended failing assertions before implementation. All OpenSpec tasks, frontend and repository verification, publication, and review refresh steps completed without exceptions.

## Global Constraints

- Run every project CLI through `nix --extra-experimental-features 'nix-command flakes' develop --command ...`.
- Do not use browser tools; verify with focused component tests, typecheck, builds, and `mix verify`.
- Do not introduce Tailwind, shadcn, a new dependency, backend/schema changes, URL state, retries, cumulative pagination, mutations, or realtime behavior.
- Keep `fetchPolicy: "network-only"` during this lifecycle-only migration.
- Keep packet and inbox pagination page-replacing. Do not use `usePaginationFragment`, because its accumulated connection edges change the approved product behavior.
- Render only caller-authored safe fallback text. Never display caught Relay or GraphQL error messages.
- Keep generated Relay types at route workflow boundaries; keep reusable UI primitives product-neutral.
- Follow TDD for each behavior slice: add or change the focused assertion, observe the intended failure, implement the minimum change, and rerun the focused test.
- Commit after every completed task below. Do not mix unrelated worktree changes into a commit.

---

## Planned File Structure

### Add

- `assets/src/ui/AsyncBoundary.tsx` — shallow Suspense plus class error boundary; accepts caller-supplied loading/error content and a reset key.
- `assets/src/ui/AsyncBoundary.test.tsx` — primitive-level suspension, safe-error, and reset recovery tests.
- `assets/app/routes/packets/formatters.test.ts` — direct coverage for shared packet date and state formatters.
- `assets/app/routes/operator/OperatorInspector.tsx` — selection-keyed readiness-validation and run-state query children with panel-scoped boundaries.

### Replace

- `assets/app/routes/productNavigation.test.ts` with `assets/app/routes/productNavigation.test.tsx` — direct configuration and rendered navigation assertions with no source-spelling checks.

### Modify

- Packet route: `route.tsx`, `workflow.ts`, `workflow.test.ts`, `types.ts`, `PacketWorkspace.tsx`, `components/PacketList.tsx`, `components/PacketDetail.tsx`, `formatters.ts`, `route.test.tsx`, `architecture.test.ts`.
- Operator route: `route.tsx`, `workflow.ts`, `types.ts`, `OperatorWorkspace.tsx`, `components/InboxList.tsx`, `components/ItemSummary.tsx`, `components/ReadinessPanel.tsx`, `components/RunPanel.tsx`, `components/VerificationPanel.tsx`, `presentation.ts`, `route.test.tsx`, `architecture.test.ts`.
- Workflow records: `openspec/changes/adopt-relay-suspense-hooks/tasks.md` and, only if implementation proves a design detail inaccurate, the already-approved change artifacts.

### Expected Unchanged Files

- `assets/app/routes/packets/data.ts` and `assets/app/routes/operator/data.ts` — reuse the existing GraphQL query documents and inline fragments.
- Backend schema and resolver files — this change is frontend lifecycle architecture only.

---

## Task 1: Add the Generic Async Boundary

**Files:**

- Create: `assets/src/ui/AsyncBoundary.tsx`
- Create: `assets/src/ui/AsyncBoundary.test.tsx`
- Modify: `assets/src/ui/importBoundaries.test.ts`
- Modify: `openspec/changes/adopt-relay-suspense-hooks/tasks.md`

### Public interface

```tsx
type AsyncBoundaryProps = {
  children: ReactNode;
  errorFallback: ReactNode;
  loadingFallback: ReactNode;
  resetKey: string | number | null;
};

export function AsyncBoundary(props: AsyncBoundaryProps): ReactElement;
```

The implementation must compose `Suspense` with a small class error boundary. The class stores only `hasError`; it does not store, inspect, log, or render the caught error. A changed `resetKey` clears `hasError` so a new route page or selected entity can render.

### TDD steps

- [x] Add a deferred-resource test that renders `loadingFallback` while a child suspends and renders the child after the promise resolves.
- [x] Run the focused test and confirm it fails because `AsyncBoundary` does not exist:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run src/ui/AsyncBoundary.test.tsx
  ```

- [x] Add a child that throws `new Error("authorization secret_alpha")`; assert only the caller's `errorFallback` is visible and neither `secret_alpha` nor the thrown message reaches the document.
- [x] Add a rerender test: first render a throwing child with `resetKey="packet:cursor_1"`, then rerender a successful child with `resetKey="packet:cursor_2"`; assert recovery without remounting the test harness.
- [x] Implement the minimal `AsyncBoundary` and add an import-boundary assertion that the primitive imports no route, Relay, or product module.
- [x] Rerun the primitive and import-boundary tests:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run src/ui/AsyncBoundary.test.tsx src/ui/importBoundaries.test.ts
  ```

- [x] Mark OpenSpec task `1.1` complete and commit:

  ```sh
  git add assets/src/ui/AsyncBoundary.tsx assets/src/ui/AsyncBoundary.test.tsx assets/src/ui/importBoundaries.test.ts openspec/changes/adopt-relay-suspense-hooks/tasks.md
  git commit -m "feat: add safe async boundary"
  ```

---

## Task 2: Migrate the Packet Read to `useLazyLoadQuery`

**Files:**

- Modify: `assets/app/routes/packets/route.tsx`
- Modify: `assets/app/routes/packets/workflow.ts`
- Modify: `assets/app/routes/packets/workflow.test.ts`
- Modify: `assets/app/routes/packets/types.ts`
- Modify: `assets/app/routes/packets/PacketWorkspace.tsx`
- Modify: `assets/app/routes/packets/components/PacketList.tsx`
- Modify: `assets/app/routes/packets/components/PacketDetail.tsx`
- Modify: `assets/app/routes/packets/route.test.tsx`
- Modify: `assets/app/routes/packets/architecture.test.ts`
- Modify: `openspec/changes/adopt-relay-suspense-hooks/tasks.md`

### Target data flow

`PacketsRoute` owns this local state:

```ts
type PacketNavigation = {
  page: PacketsPage;
  previousCursors: Array<string | null>;
};

const [navigation, setNavigation] = useState<PacketNavigation>(...);
const [requestedSelectedId, setRequestedSelectedId] = useState<string | null>(null);
```

It renders a route-level `AsyncBoundary` keyed by `page.after ?? "initial"`. The query child calls:

```ts
useLazyLoadQuery<PacketsRouteOperation>(
  PacketsRouteQuery,
  page,
  { fetchPolicy: "network-only" }
);
```

`workflow.ts` keeps the generated-type mapping and loaded-data derivation, but contains no `fetchQuery`, `useRelayEnvironment`, subscription, effect, or `QueryState`. Its connection result is exactly:

```ts
export type PacketConnection<TPacket> = {
  hasNextPage: boolean;
  nextCursor: string | null;
  rows: TPacket[];
};
```

The effective selection is computed during render: use `requestedSelectedId` when it exists on the loaded page, otherwise use the first row id, otherwise `null`. Next/previous handlers set `requestedSelectedId` to `null` before changing the cursor. There is no effect that mirrors the effective id back into state.

### TDD steps

- [x] Rewrite `workflow.test.ts` around exported pure mapping/selection helpers. Add exact-shape coverage proving the connection contains only `rows`, `hasNextPage`, and `nextCursor`, and that `hasNextPage` becomes false when Relay omits `endCursor`.
- [x] Strengthen `route.test.tsx` so a deferred initial request shows `Loading packets...`; a deferred page request shows `Loading packet page...` with no previous-page packet; and the resolved replacement page selects its first packet.
- [x] Keep the current safe initial/page error assertions and make the page-error test prove old rows, detail, and pagination are absent while sensitive server text is not rendered.
- [x] Update `architecture.test.ts` to require `useLazyLoadQuery` and forbid `fetchQuery`, `useRelayEnvironment`, `QueryState`, subscription cleanup, and packet query-lifecycle effects.
- [x] Run the packet tests and confirm the new mapping/architecture expectations fail against the subscription implementation:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/workflow.test.ts app/routes/packets/route.test.tsx app/routes/packets/architecture.test.ts
  ```

- [x] Implement the route shell, loaded query child, safe packet loading/error workspaces, lean mapper, render-time selection, and cursor-history handlers.
- [x] Change `PacketWorkspace`, `PacketList`, and `PacketDetail` to explicit loaded-data props. Remove every `PacketsWorkflowState[...]` and query-state-driven loading/error branch from product components; loading/error content belongs to the route boundary fallbacks.
- [x] Delete packet `FetchStatus` and `QueryState`, plus `idleQueryState`, `startLoading`, `successQueryState`, `errorQueryState`, and direct Relay subscription imports.
- [x] Rerun focused tests, Relay validation, and typecheck:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/workflow.test.ts app/routes/packets/route.test.tsx app/routes/packets/architecture.test.ts
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run relay:check
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run typecheck
  ```

- [x] Mark OpenSpec task `2.1` complete and commit:

  ```sh
  git add assets/app/routes/packets openspec/changes/adopt-relay-suspense-hooks/tasks.md
  git commit -m "refactor: render packet reads with Relay hooks"
  ```

---

## Task 3: Consolidate Packet Formatting and Make Navigation Tests Behavioral

**Files:**

- Create: `assets/app/routes/packets/formatters.test.ts`
- Modify: `assets/app/routes/packets/formatters.ts`
- Modify: `assets/app/routes/packets/components/PacketList.tsx`
- Modify: `assets/app/routes/packets/components/PacketDetail.tsx`
- Delete: `assets/app/routes/productNavigation.test.ts`
- Create: `assets/app/routes/productNavigation.test.tsx`
- Modify: `openspec/changes/adopt-relay-suspense-hooks/tasks.md`

### Target formatter interface

```ts
export function formatPacketState(value: string): string;
export function formatPacketUpdatedAt(value: string): string;
```

### TDD steps

- [x] Add formatter cases for `ready_for_run -> Ready for run`, mixed-case input normalization, and the existing UTC updated-at output.
- [x] Replace filesystem/source-string navigation tests with a direct equality assertion on `PRODUCT_DESTINATIONS` and rendered assertions for both product layouts: linked destinations have the right `href`, disabled destinations remain non-links, and the active route gets `aria-current="page"`.
- [x] Run the focused tests and confirm the missing formatter and changed test extension fail:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/formatters.test.ts app/routes/productNavigation.test.tsx
  ```

- [x] Implement `formatPacketState`, import it in list/detail, and remove both local `formatState` functions.
- [x] Rerun the formatter, navigation, and packet route tests:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/formatters.test.ts app/routes/productNavigation.test.tsx app/routes/packets/route.test.tsx
  ```

- [x] Mark OpenSpec task `2.2` complete and commit:

  ```sh
  git add assets/app/routes/packets/formatters.ts assets/app/routes/packets/formatters.test.ts assets/app/routes/packets/components/PacketList.tsx assets/app/routes/packets/components/PacketDetail.tsx assets/app/routes/productNavigation.test.ts assets/app/routes/productNavigation.test.tsx openspec/changes/adopt-relay-suspense-hooks/tasks.md
  git commit -m "refactor: consolidate packet presentation helpers"
  ```

---

## Task 4: Migrate the Operator Inbox Root Read

**Files:**

- Modify: `assets/app/routes/operator/route.tsx`
- Modify: `assets/app/routes/operator/workflow.ts`
- Modify: `assets/app/routes/operator/types.ts`
- Modify: `assets/app/routes/operator/OperatorWorkspace.tsx`
- Modify: `assets/app/routes/operator/components/InboxList.tsx`
- Modify: `assets/app/routes/operator/components/ItemSummary.tsx`
- Modify: `assets/app/routes/operator/route.test.tsx`
- Modify: `assets/app/routes/operator/architecture.test.ts`
- Modify: `openspec/changes/adopt-relay-suspense-hooks/tasks.md`

### Target data flow

`OperatorRoute` owns `OperatorInboxPage`, previous cursors, and requested selected id. A route-level boundary keyed by the inbox cursor wraps a loaded child whose workflow calls:

```ts
useLazyLoadQuery<OperatorWorkflowRouteOperation>(
  OperatorWorkflowRouteQuery,
  inboxPage,
  { fetchPolicy: "network-only" }
);
```

The loaded workflow returns mapped inbox metadata, rows, effective selection, selected item, derived readiness/input, and linked run id. It does not return `inboxQuery` or `itemQuery`. `InboxList` receives explicit `rows`, `sourceWatermark`, `hasMore`, cursor navigation flags/callbacks, selection, and selection callback. `ItemSummary` receives only the selected item because the selected item is already part of the loaded inbox projection.

Next/previous handlers clear requested selection before changing the page. Effective selection is derived during render; do not add a synchronization effect.

### TDD steps

- [x] Add a deferred-root test that renders a safe `Loading inbox...` route workspace before the query resolves.
- [x] Change root failure coverage to expect a caller-authored `Unable to load operator inbox.` message and assert neither a thrown secret nor a GraphQL error message is rendered.
- [x] Make pagination coverage prove a deferred next page removes the prior row, shows loading, then renders only the replacement row selected by default.
- [x] Preserve current empty/null-connection, default selection, explicit row selection, detail, affordance-redaction, and navigation assertions.
- [x] Update architecture coverage to require `useLazyLoadQuery` and forbid root `fetchQuery`, `useRelayEnvironment`, inbox `QueryState`, and subscription cleanup.
- [x] Run focused tests and confirm the new loading/safe-error/architecture assertions fail:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/operator/route.test.tsx app/routes/operator/architecture.test.ts
  ```

- [x] Implement the route shell and loaded workflow. Add safe loading/error `OperatorWorkspace` variants that retain the product shell but contain no stale selected item.
- [x] Simplify `InboxList` and `ItemSummary` to loaded explicit props. Remove stale-query, query-error, and item-query branches from both components.
- [x] Keep readiness and run-state behavior temporarily compiling through the existing APIs; do not mark task `3.3` yet because dependent reads still use query state until Task 5.
- [x] Rerun the focused route tests and typecheck:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/operator/route.test.tsx app/routes/operator/architecture.test.ts
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run typecheck
  ```

- [x] Mark OpenSpec task `3.1` complete and commit:

  ```sh
  git add assets/app/routes/operator openspec/changes/adopt-relay-suspense-hooks/tasks.md
  git commit -m "refactor: render operator inbox with Relay hooks"
  ```

---

## Task 5: Isolate Operator Readiness and Run-State Queries by Panel

**Files:**

- Create: `assets/app/routes/operator/OperatorInspector.tsx`
- Modify: `assets/app/routes/operator/OperatorWorkspace.tsx`
- Modify: `assets/app/routes/operator/workflow.ts`
- Modify: `assets/app/routes/operator/types.ts`
- Modify: `assets/app/routes/operator/components/ReadinessPanel.tsx`
- Modify: `assets/app/routes/operator/components/RunPanel.tsx`
- Modify: `assets/app/routes/operator/components/VerificationPanel.tsx`
- Modify: `assets/app/routes/operator/presentation.ts`
- Modify: `assets/app/routes/operator/route.test.tsx`
- Modify: `assets/app/routes/operator/architecture.test.ts`
- Modify: `openspec/changes/adopt-relay-suspense-hooks/tasks.md`

### Target inspector flow

`OperatorWorkspace` renders `OperatorInspector` with a React `key` equal to the effective selected id. That remount resets validation intent whenever selection changes without a cleanup effect.

`OperatorInspector` initially renders locally derived readiness. Clicking `Validate readiness` sets a local validation request flag and conditionally mounts a query child that calls:

```ts
useLazyLoadQuery<OperatorPacketReadinessOperation>(
  OperatorPacketReadinessQuery,
  { input: packetReadinessQueryInput(readinessInput) },
  { fetchPolicy: "network-only" }
);
```

The readiness boundary is keyed by selected id plus a validation request identity. Its loading fallback keeps the derived readiness visible with a disabled `Validating readiness` button. Its error fallback renders a safe panel message and leaves the inbox/detail intact.

When the selected item has a run id, a separate query child calls:

```ts
useLazyLoadQuery<OperatorRunStateOperation>(
  OperatorRunStateQuery,
  { id: runId },
  { fetchPolicy: "network-only" }
);
```

That child renders both `RunPanel` and `VerificationPanel` from one loaded result. Its boundary is keyed by selected id plus run id. Loading/error fallbacks replace only those inspector panels. An item without a run renders the existing no-run/no-verification states without issuing a query.

### Component contracts

- `ReadinessPanel` receives readiness data, readiness input, optional validation callback, and `isValidating`; it receives no query state and never sees an error object.
- `RunPanel` receives `runId`, optional loaded run state, and a display mode of loaded/loading/error/empty (or equivalent explicit discriminated props); it receives no query state or error object.
- `VerificationPanel` receives `ReturnType<typeof verificationOutcomeFromRunState> | null` directly and no workflow-indexed type.
- `presentation.ts` no longer exports `isQueryLoading` and no longer imports `QueryState`.

### TDD steps

- [x] Add a deferred readiness-validation test: after the click, assert the derived panel remains visible, the button says `Validating readiness`, and the inbox plus selected detail remain visible until the backend result arrives.
- [x] Add a readiness rejection test with sensitive text; assert a safe `Unable to validate packet readiness.` panel message, no sensitive text, and unchanged inbox/detail context.
- [x] Preserve the current assertion that readiness is not requested before the validation event and that the request variables exactly match the derived input.
- [x] Extend the current deferred run-state selection test so the loading replacement is panel-scoped and no prior run/verification result remains visible.
- [x] Add a run-state rejection test with sensitive text; assert safe run/verification fallbacks, no sensitive text, and the inbox, selected detail, and locally derived readiness remain visible.
- [x] Update architecture coverage to forbid every `fetchQuery`, `useRelayEnvironment`, `QueryState`, transition helper, subscription, and query-lifecycle effect in the operator route tree while requiring `useLazyLoadQuery` for all three product reads.
- [x] Run the focused route/architecture tests and confirm the new isolation and cleanup assertions fail:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/operator/route.test.tsx app/routes/operator/architecture.test.ts
  ```

- [x] Implement `OperatorInspector`, the conditional readiness/run query children, safe panel fallbacks, and generated-type mapping helpers.
- [x] Delete the validation token/ref/subscription machinery, `useOperatorRunStateRelayQuery`, all query-state transition helpers, error normalization, and the remaining operator `QueryState`/`FetchStatus` types.
- [x] Convert all inspector components to the explicit contracts above and remove `isQueryLoading`.
- [x] Rerun operator tests, all import boundaries, Relay validation, and typecheck:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/operator/route.test.tsx app/routes/operator/data.test.ts app/routes/operator/architecture.test.ts src/ui/importBoundaries.test.ts
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run relay:check
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run typecheck
  ```

- [x] Mark OpenSpec tasks `3.2` and `3.3` complete and commit:

  ```sh
  git add assets/app/routes/operator openspec/changes/adopt-relay-suspense-hooks/tasks.md
  git commit -m "refactor: isolate operator Relay query panels"
  ```

---

## Task 6: Verify the Integrated Change and Update Workflow Records

**Files:**

- Modify: `openspec/changes/adopt-relay-suspense-hooks/tasks.md`
- Modify only if evidence requires it: `openspec/changes/adopt-relay-suspense-hooks/design.md`
- Verify: all files changed since `4ded4ec`

### Verification steps

- [x] Search the product route trees for lifecycle leftovers. Expected result: no matches for the removed machinery; `useEffect` is acceptable only if a concrete non-query behavior still requires it and the reason is documented in the diff review.

  ```sh
  rg -n "fetchQuery|useRelayEnvironment|QueryState|idleQueryState|loadingQueryState|startLoading|successQueryState|errorQueryState|subscription\.unsubscribe" assets/app/routes/operator assets/app/routes/packets
  ```

- [x] Run the entire frontend verification gate:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run verify
  ```

- [x] Strictly validate both active OpenSpec changes:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate add-packets-route --strict
  nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate adopt-relay-suspense-hooks --strict
  ```

- [x] Run the repository release gate and whitespace check:

  ```sh
  nix --extra-experimental-features 'nix-command flakes' develop --command mix verify
  git diff --check
  ```

- [x] Review `git diff 4ded4ec...HEAD` against every scenario in the two delta specs. Confirm no backend, schema, dependency, styling-system, URL-state, retry, mutation, realtime, or cumulative-pagination change slipped in.
- [x] Confirm the archive dependency is still explicit: `add-packets-route` must be synced/archived before `adopt-relay-suspense-hooks` because the latter's packet requirements are based on the former.
- [x] Mark OpenSpec task `4.1` complete and commit the final task bookkeeping:

  ```sh
  git add openspec/changes/adopt-relay-suspense-hooks/tasks.md
  git commit -m "docs: complete Relay Suspense migration"
  ```

- [x] Confirm the worktree is clean, push the current branch, refresh PR #12 through `gh`, and inspect thread-aware bot review state without browser tools.

---

## Plan Self-Review Checklist

- [x] Every OpenSpec task (`1.1`, `2.1`, `2.2`, `3.1`, `3.2`, `3.3`, `4.1`) maps to at least one implementation task above.
- [x] Every new behavior starts with a focused failing test and names its expected failure.
- [x] Every task names exact files, exact Nix-wrapped commands, and a commit boundary.
- [x] All new interfaces are concrete; there are no placeholders, TODOs, or undecided technology choices.
- [x] Root failures are route-scoped; readiness and run failures are panel-scoped; no caught error text reaches the UI.
- [x] Local state is limited to cursor variables/history, requested selection, and readiness-validation intent.
- [x] Packet and inbox page replacement and selection reset are preserved without derived-state synchronization effects.
- [x] The plan removes unused packet connection fields, duplicate packet state formatting, and source-spelling navigation tests in addition to the query-state duplication.
- [x] Final verification covers Relay, TypeScript, import boundaries, all frontend tests/builds, both OpenSpec changes, `mix verify`, diff hygiene, push, and PR review refresh.
