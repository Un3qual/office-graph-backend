## 1. Architecture Baseline Tests

- [ ] 1.1 Add failing frontend tests for a GraphQL-only operator route wrapped in a TanStack Query client.
- [ ] 1.2 Add failing query-hook tests proving operator workflow reads call GraphQL and normalize frontend view models.
- [ ] 1.3 Add a failing boundary test proving production operator UI code does not import the legacy JSON API client.

## 2. New Operator Frontend Module

- [ ] 2.1 Create the `assets/src/operator` module with workflow types, query keys, GraphQL transport, query documents, response mappers, and derived workflow helpers.
- [ ] 2.2 Build TanStack Query hooks for inbox, selected item detail, packet readiness, and linked run state.
- [ ] 2.3 Build focused route, workspace, layout, inbox, item summary, readiness, run, and verification components over the new view models.
- [ ] 2.4 Repoint `App.tsx` and `main.tsx` to mount the new operator route through `QueryClientProvider`.

## 3. Demo Removal

- [ ] 3.1 Delete the obsolete `assets/src/operator-workflow` implementation and demo-only tests.
- [ ] 3.2 Remove or simplify the `assets/src/foundation/foundationStack.*` TanStack proof once the real operator route owns the pattern.
- [ ] 3.3 Keep shared UI primitives, design tokens, and generic components free of operator workflow status or transport logic.

## 4. Spec And Verification

- [ ] 4.1 Validate `rebuild-operator-frontend-foundation` with OpenSpec strict mode.
- [ ] 4.2 Run focused frontend tests for the new operator module and app route.
- [ ] 4.3 Run full frontend verification from the Nix shell.
- [ ] 4.4 Run Phoenix app-shell tests, formatting, compile warnings-as-errors, and `git diff --check`.
- [ ] 4.5 Update task checkboxes and commit the completed frontend reset.
