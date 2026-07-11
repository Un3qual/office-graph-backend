# PR 12 Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Correct all three valid bot findings on PR #12, verify the branch, push the fixes, and reply to each addressed inline thread.

**Architecture:** Normalize Relay pagination at the route workflow boundary so UI state cannot advertise an unusable cursor. Keep product destinations in one route-owned module while shared UI remains generic, and use the existing CSS border token for packet detail rows. Each repair gets its own failing regression test and focused commit before the full repository gate and GitHub follow-through.

**Tech Stack:** TypeScript 5.8, React 19, React Router 8.1, Relay 21, Vitest 3.2, plain CSS design tokens, project Nix flake, OpenSpec, GitHub CLI.

> **Archive status:** Completed. The three repairs, their intended RED/GREEN cycles, full verification, push, thread replies, and final review refresh all completed without exceptions.

## Global Constraints

- Use `nix --extra-experimental-features 'nix-command flakes' develop --command ...` for all project tools.
- OpenSpec remains the source of truth; these fixes must conform to `openspec/changes/add-packets-route/` without expanding its scope.
- Shared UI under `assets/src/ui` must remain generic and product-vocabulary-free.
- Product labels and routes must remain route-owned under `assets/app/routes`.
- Relay remains the sole owner of packet GraphQL server state.
- Tailwind, Tailwind-dependent libraries, LiveView product UI, new dependencies, and new API fields are forbidden.
- Do not change packet selection, cursor-history, or safe-error semantics beyond preventing unusable next-page state.
- Use test-first cycles: add one focused failing regression, observe the expected failure, implement the smallest repair, and observe the focused suite passing.
- Keep each finding in a separate commit and push only to the existing `codex/do-next-task` branch for PR #12.
- Do not use browser tools.

---

### Task 1: Normalize Nullable Relay Pagination Cursors

**Files:**
- Modify: `assets/app/routes/packets/workflow.test.ts:104`
- Modify: `assets/app/routes/packets/workflow.ts:146-155`

**Interfaces:**
- Consumes: Relay `pageInfo.hasNextPage: boolean` and `pageInfo.endCursor: string | null | undefined`.
- Produces: `PacketConnection.hasNextPage: boolean` that is true only when `PacketConnection.nextCursor: string | null` is non-null.

- [x] **Step 1: Add the failing nullable-cursor workflow regression**

Insert this test before the pagination-failure test in `workflow.test.ts`:

```ts
  it("disables forward pagination when Relay omits the end cursor", async () => {
    const network = vi.fn(async (): Promise<GraphQLResponse> =>
      packetConnectionResponse([packet()], {
        hasNextPage: true,
        endCursor: null
      })
    );
    const workflow = renderWorkflow(network);

    await waitFor(() => expect(workflow.result.current.packetQuery.isSuccess).toBe(true));
    expect(workflow.result.current.packetQuery.data?.hasNextPage).toBe(false);
    expect(workflow.result.current.packetQuery.data?.nextCursor).toBeNull();

    act(() => workflow.result.current.loadNextPage());

    expect(network).toHaveBeenCalledOnce();
    expect(workflow.result.current.packetPage).toEqual({ first: 50, after: null });
  });
```

- [x] **Step 2: Run the focused test and confirm the intended failure**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/workflow.test.ts
```

Expected: FAIL in `disables forward pagination when Relay omits the end cursor` because the current workflow exposes `hasNextPage` as `true`.

- [x] **Step 3: Normalize the cursor once at the workflow boundary**

In `packetConnectionFromRelay`, compute the cursor before returning and use it for both fields:

```ts
  const nextCursor = connection.pageInfo.endCursor ?? null;

  return {
    after: page.after,
    empty: rows.length === 0,
    first: page.first,
    hasNextPage: connection.pageInfo.hasNextPage && nextCursor !== null,
    hasPreviousPage: connection.pageInfo.hasPreviousPage,
    nextCursor,
    startCursor: connection.pageInfo.startCursor ?? null,
    rows
  };
```

- [x] **Step 4: Run the focused test and confirm it passes**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/workflow.test.ts
```

Expected: all six packet workflow tests pass with no warnings or unhandled errors.

- [x] **Step 5: Commit the pagination repair**

Run:

```bash
git add assets/app/routes/packets/workflow.test.ts assets/app/routes/packets/workflow.ts
git commit -m "fix: disable unusable packet pagination"
```

Expected: one commit containing only the nullable-cursor regression and normalization.

### Task 2: Centralize Route-Owned Product Destinations

**Files:**
- Create: `assets/app/routes/productNavigation.ts`
- Create: `assets/app/routes/productNavigation.test.ts`
- Modify: `assets/app/routes/operator/components/OperatorLayout.tsx:1-22`
- Modify: `assets/app/routes/packets/components/PacketsLayout.tsx:1-21`

**Interfaces:**
- Consumes: generic `NavDestination` type from `assets/src/ui/NavRail.tsx`.
- Produces: `PRODUCT_DESTINATIONS`, a readonly route-owned descriptor list consumed by both product layouts.

- [x] **Step 1: Add the failing product-navigation module test**

Create `assets/app/routes/productNavigation.test.ts`:

```ts
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { PRODUCT_DESTINATIONS } from "./productNavigation";

describe("product navigation configuration", () => {
  it("provides one route-owned destination list for every workspace", () => {
    expect(PRODUCT_DESTINATIONS).toEqual([
      { label: "Operator", to: "/operator" },
      { label: "Packets", to: "/packets" },
      { label: "All Runs" },
      { label: "Entities" },
      { label: "Reports" }
    ]);

    const routeRoot = join(process.cwd(), "app/routes");
    const layoutSources = [
      "operator/components/OperatorLayout.tsx",
      "packets/components/PacketsLayout.tsx"
    ].map((path) => readFileSync(join(routeRoot, path), "utf8"));

    for (const source of layoutSources) {
      expect(source).toContain('import { PRODUCT_DESTINATIONS } from "../../productNavigation"');
      expect(source).toContain("destinations={PRODUCT_DESTINATIONS}");
      expect(source).not.toContain("destinations={[");
    }
  });
});
```

- [x] **Step 2: Run the new test and confirm the intended failure**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/productNavigation.test.ts
```

Expected: FAIL because `./productNavigation` does not exist. After the module
is created, the same test still guards that both layouts consume the shared
constant instead of reintroducing inline arrays.

- [x] **Step 3: Create the typed route-owned destination constant**

Create `assets/app/routes/productNavigation.ts`:

```ts
import type { NavDestination } from "../../src/ui/NavRail";

export const PRODUCT_DESTINATIONS = [
  { label: "Operator", to: "/operator" },
  { label: "Packets", to: "/packets" },
  { label: "All Runs" },
  { label: "Entities" },
  { label: "Reports" }
] as const satisfies readonly NavDestination[];
```

- [x] **Step 4: Replace both inline arrays with the shared route constant**

Add this import to both layout files:

```ts
import { PRODUCT_DESTINATIONS } from "../../productNavigation";
```

Replace each inline `destinations={[...]}` value with:

```tsx
      destinations={PRODUCT_DESTINATIONS}
```

- [x] **Step 5: Run navigation, route, and boundary verification**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/productNavigation.test.ts app/routes/operator/route.test.tsx app/routes/packets/route.test.tsx src/ui/importBoundaries.test.ts
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets run typecheck
```

Expected: the product-navigation test, operator route tests, packet route tests, shared UI boundary tests, and TypeScript typecheck all pass. `assets/src/ui` remains free of product labels and route imports.

- [x] **Step 6: Commit the navigation repair**

Run:

```bash
git add assets/app/routes/productNavigation.ts assets/app/routes/productNavigation.test.ts assets/app/routes/operator/components/OperatorLayout.tsx assets/app/routes/packets/components/PacketsLayout.tsx
git commit -m "refactor: share product navigation destinations"
```

Expected: one commit containing only the shared route-owned configuration, its test, and the two consumers.

### Task 3: Use the Packet Border Design Token

**Files:**
- Modify: `assets/app/routes/packets/route.test.tsx:175-190`
- Modify: `assets/src/styles/global.css:553-559`

**Interfaces:**
- Consumes: the existing `--og-color-border` CSS custom property.
- Produces: `.packet-detail-list div` borders that follow the shared border token.

- [x] **Step 1: Add the failing packet-detail token assertion**

Insert this test after the compact-list style test in `route.test.tsx`:

```ts
  it("uses the border design token for packet detail rows", () => {
    const styles = readFileSync(join(process.cwd(), "src/styles/global.css"), "utf8");
    const detailRows = styles.match(/\.packet-detail-list div\s*\{([^}]*)\}/)?.[1] ?? "";

    expect(detailRows).toContain(
      "border-bottom: 1px solid var(--og-color-border);"
    );
    expect(detailRows).not.toContain("#edf1f3");
  });
```

- [x] **Step 2: Run the packet route test and confirm the intended failure**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/route.test.tsx
```

Expected: FAIL in `uses the border design token for packet detail rows` because the rule still contains `#edf1f3`.

- [x] **Step 3: Replace the hardcoded border color**

Change the packet detail row rule to:

```css
.packet-detail-list div {
  display: grid;
  grid-template-columns: minmax(140px, 0.35fr) minmax(0, 1fr);
  gap: 20px;
  border-bottom: 1px solid var(--og-color-border);
  padding: 13px 0;
}
```

- [x] **Step 4: Run the focused route test and confirm it passes**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/packets/route.test.tsx
```

Expected: all packet route tests pass with the new token assertion.

- [x] **Step 5: Commit the CSS repair**

Run:

```bash
git add assets/app/routes/packets/route.test.tsx assets/src/styles/global.css
git commit -m "fix: use packet border design token"
```

Expected: one commit containing only the failing style regression and CSS token replacement.

### Task 4: Verify, Push, Refresh, and Reply

**Files:**
- Verify: all files changed by Tasks 1-3
- Verify: `openspec/changes/add-packets-route/`

**Interfaces:**
- Consumes: the three focused commits and PR #12's current thread-aware GitHub state.
- Produces: a verified pushed branch and evidence-backed replies on review comments `3560469564`, `3560497651`, and `3560497653`.

- [x] **Step 1: Run the repository verification gate**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command mix verify
```

Expected: Credo, duplication, architecture, ExUnit, Relay validation, TypeScript, all Vitest tests, React Router builds, and app-shell verification pass.

- [x] **Step 2: Validate the accepted OpenSpec change and diff hygiene**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate add-packets-route --strict
git diff --check origin/main...HEAD
git status --short --branch
git log --oneline --decorate -6
```

Expected: strict OpenSpec validation succeeds, diff checking emits no output, the worktree is clean, and the three repair commits follow the design and plan commits.

- [x] **Step 3: Push the current branch**

Run:

```bash
git push origin codex/do-next-task
```

Expected: `origin/codex/do-next-task` advances to the final repair commit and PR #12 updates without creating another branch or PR.

- [x] **Step 4: Refresh complete thread-aware review state after the push**

Run:

```bash
python3 /Users/admin/.codex/plugins/cache/openai-curated-remote/github/0.1.8-2841cf9749ae/skills/gh-address-comments/scripts/fetch_comments.py
gh pr view 12 --json number,url,headRefName,headRefOid,statusCheckRollup
```

Expected: the PR head matches local `HEAD`. Reclassify every current bot thread, including outdated, outside-diff, duplicate, and newly posted items. If a new bot-last thread is actionable, return to the appropriate test-first task before replying.

- [x] **Step 5: Reply to the three addressed inline comments**

Run:

```bash
gh api --method POST repos/Un3qual/office-graph-backend/pulls/12/comments/3560469564/replies -f body='Fixed by normalizing Relay page state so hasNextPage requires a non-null end cursor. Added a regression proving the workflow does not issue another request for the inconsistent state. Focused Vitest and the full mix verify gate pass.'
gh api --method POST repos/Un3qual/office-graph-backend/pulls/12/comments/3560497651/replies -f body='Fixed by extracting PRODUCT_DESTINATIONS into the route-owned app/routes/productNavigation.ts module and using it from both layouts. Product vocabulary remains outside shared UI. Route, boundary, typecheck, and full mix verify checks pass.'
gh api --method POST repos/Un3qual/office-graph-backend/pulls/12/comments/3560497653/replies -f body='Fixed by replacing the hardcoded packet detail border with var(--og-color-border) and adding a focused stylesheet regression. Packet route tests and the full mix verify gate pass.'
```

Expected: each API call returns the newly created reply in its original inline review thread. Do not resolve threads unless the user separately requests resolution.

- [x] **Step 6: Perform the final post-reply refresh**

Run:

```bash
python3 /Users/admin/.codex/plugins/cache/openai-curated-remote/github/0.1.8-2841cf9749ae/skills/gh-address-comments/scripts/fetch_comments.py
gh pr view 12 --json number,url,headRefOid,statusCheckRollup
git status --short --branch
```

Expected: the pushed PR head still matches local `HEAD`, the worktree is clean, all previously actionable threads have an evidence-backed reply, and no new current actionable bot-last thread remains. Pending asynchronous bot checks may continue, but any completed check with actionable feedback must be handled before completion.
