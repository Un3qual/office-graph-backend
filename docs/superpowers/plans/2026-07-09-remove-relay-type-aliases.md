# Remove Relay Type Aliases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove cosmetic aliases that disguise generated Relay fragment data as independent route models while preserving the operator console's existing behavior.

**Architecture:** Generated Relay `$data` types remain authoritative inside the route data and derivation boundary. `types.ts` retains only client-owned query, pagination, input, and locally derived readiness state; route components obtain their public prop types from `OperatorWorkflowState` instead of importing renamed GraphQL response aliases.

**Tech Stack:** TypeScript 5.8, React 19, Relay 21.0.1, Vitest 3.2, OpenSpec 1.4.1, project Nix flake.

## Global Constraints

- Use the project Nix flake for runtime and CLI commands.
- Relay remains the product GraphQL server-state model.
- Product GraphQL data uses generated Relay types rather than a parallel homemade view-model layer.
- Preserve all existing loading, empty, error, selected-row, readiness, run, and verification behavior.
- Do not add Tailwind CSS, TanStack Query, or new product behavior.

---

### Task 1: Make generated Relay types explicit at the route boundary

**Files:**
- Modify: `assets/app/routes/operator/architecture.test.ts`
- Modify: `assets/app/routes/operator/types.ts`
- Modify: `assets/app/routes/operator/workflow.ts`
- Modify: `assets/app/routes/operator/derived.ts`
- Modify: `assets/app/routes/operator/presentation.ts`
- Modify: `assets/app/routes/operator/components/InboxList.tsx`
- Modify: `assets/app/routes/operator/components/ItemSummary.tsx`
- Modify: `assets/app/routes/operator/components/ReadinessPanel.tsx`
- Modify: `assets/app/routes/operator/components/RunPanel.tsx`
- Modify: `assets/app/routes/operator/components/VerificationPanel.tsx`
- Modify: `openspec/changes/design-product-frontend-platform/tasks.md`

**Interfaces:**
- Consumes: Relay-generated `OperatorWorkflowItemFragment$data`, `OperatorPacketReadinessFragment$data`, and `OperatorRunStateFragment$data` types.
- Produces: `OperatorWorkflowState`, whose fields remain the public route-component contract; generic `OperatorInbox<TItem>` and `DerivedPacketReadiness<TCommand>` client-owned state types.

- [x] **Step 1: Write the failing architecture test**

Add a test that reads `types.ts` and `workflow.ts` and requires route-local types to avoid generated artifacts while requiring `workflow.ts` to use generated fragment data directly:

```ts
it("keeps generated Relay data types explicit at the route data boundary", () => {
  const typesSource = readFileSync(join(routeRoot, "types.ts"), "utf8");
  const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");

  expect(typesSource).not.toContain("__generated__");
  expect(typesSource).not.toContain("Fragment$data");
  expect(typesSource).not.toContain('" $fragmentType"');
  expect(workflowSource).toContain("OperatorWorkflowItemFragment$data");
  expect(workflowSource).toContain("OperatorPacketReadinessFragment$data");
  expect(workflowSource).toContain("OperatorRunStateFragment$data");
});
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/operator/architecture.test.ts
```

Expected: FAIL because `types.ts` imports `__generated__` fragment types and `workflow.ts` does not yet use the generated `$data` types directly.

- [x] **Step 3: Remove cosmetic generated-data aliases**

Change `types.ts` so it exports only client-owned contracts. Make the inbox generic and model the locally derived readiness preview explicitly:

```ts
export type OperatorInbox<TItem> = {
  type: "operator_inbox";
  empty: boolean;
  hasMore: boolean;
  limit: number;
  nextCursor: string | null;
  afterCursor: string | null;
  sourceWatermark: string | null;
  rows: TItem[];
};

export type DerivedPacketReadiness<TCommand> = {
  type: "packet_readiness";
  ready: false;
  status: "blocked";
  allowedNextActions: string[];
  commandAffordances: TCommand[];
  blockerReasons: string[];
  sourceLinks: Array<{ title: string }>;
  requiredChecks: Array<{ state: string }>;
  sourceWatermark: string | null;
  isDerived: true;
};
```

Delete `OperatorWorkflowItem`, `OperatorCommandAffordance`, `PacketReadiness`, `OperatorRunState`, and `VerificationOutcome` from `types.ts`.

- [x] **Step 4: Use generated types directly in data and derivation code**

Import generated `$data` types into `workflow.ts`, `derived.ts`, and `presentation.ts`. Replace cosmetic aliases with the generated names. In `workflow.ts`, define the meaningful server-or-derived readiness union:

```ts
type PacketReadinessState =
  | OperatorPacketReadinessFragment$data
  | ReturnType<typeof packetReadinessForItem>;
```

Use `OperatorInbox<OperatorWorkflowItemFragment$data>`, `QueryState<OperatorRunStateFragment$data>`, and generated fragment `$data` return types directly. Let `verificationOutcomeFromRunState` infer its client-owned return object.

- [x] **Step 5: Type component props from the hook contract**

Replace imports of the removed aliases in route components with type-only access through `OperatorWorkflowState`, for example:

```ts
import type { OperatorWorkflowState } from "../workflow";

type Props = {
  readiness: OperatorWorkflowState["readiness"];
  readinessInput: OperatorWorkflowState["readinessInput"];
  readinessQuery: OperatorWorkflowState["readinessQuery"];
  onValidateReadiness: OperatorWorkflowState["validatePacketReadiness"];
};
```

Use the corresponding indexed fields for inbox, item, run, and verification component props.

- [x] **Step 6: Run focused verification and verify GREEN**

Run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets exec vitest run app/routes/operator/architecture.test.ts app/routes/operator/route.test.tsx
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets typecheck
```

Expected: all tests pass and TypeScript reports no errors.

- [x] **Step 7: Mark the OpenSpec follow-up complete and run full verification**

Change task 3.5 to checked, then run:

```bash
nix --extra-experimental-features 'nix-command flakes' develop --command openspec validate design-product-frontend-platform --strict
nix --extra-experimental-features 'nix-command flakes' develop --command pnpm --dir assets verify
nix --extra-experimental-features 'nix-command flakes' develop --command mix precommit
```

Expected: OpenSpec validation, frontend verification, and backend precommit all pass.

Actual: strict OpenSpec validation passed and the full frontend verification passed with 33 tests plus the production build and app-shell check. Backend `mix precommit` reached `static.analysis` and stopped on two pre-existing Credo refactoring findings in `lib/office_graph/projections/operator_workflow.ex:862` and `:875`; this change does not modify that file.

- [x] **Step 8: Commit the verified refactor**

```bash
git add assets/app/routes/operator openspec/changes/design-product-frontend-platform/tasks.md docs/superpowers/plans/2026-07-09-remove-relay-type-aliases.md
git commit -m "refactor: use generated relay types directly"
```
