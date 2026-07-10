## 1. Generic Async Boundary

- [x] 1.1 Add failing component tests for caller-supplied Suspense fallback,
  safe error fallback, and reset-key recovery; implement the shallow generic
  async boundary under `assets/src/ui/` and run the focused primitive tests.

## 2. Packet Relay Hook Migration

- [x] 2.1 Add failing packet route and workflow tests for render-time Relay
  loading, safe initial and pagination errors, page-replacement selection, and
  the lean packet connection shape; migrate the route to `useLazyLoadQuery`
  under the generic boundary and remove packet `QueryState` lifecycle code.
- [x] 2.2 Add failing formatter coverage, move packet state formatting into the
  route formatter module, and replace product-navigation source-spelling tests
  with direct configuration and rendered-behavior assertions.

## 3. Operator Relay Hook Migration

- [x] 3.1 Add failing operator tests for Suspense-driven inbox loading and safe
  route errors; migrate the inbox root read to `useLazyLoadQuery` while
  preserving cursor history, selection, empty state, and existing detail.
- [x] 3.2 Add failing operator tests proving readiness-validation and run-state
  loading or failure stay panel-scoped; migrate those dependent reads to
  conditional Relay query children or preloaded-query hooks and key their
  boundaries to the selected identity or validation request.
- [x] 3.3 Remove unused operator query-state types, transition helpers, and
  direct product-read `fetchQuery` imports; update import-boundary coverage and
  run Relay validation, focused route tests, and TypeScript typecheck.

## 4. Change Verification

- [x] 4.1 Run frontend verification, strict validation for both active OpenSpec
  changes, the project `mix verify` gate, and `git diff --check`; document the
  required archive order for the two changes.
