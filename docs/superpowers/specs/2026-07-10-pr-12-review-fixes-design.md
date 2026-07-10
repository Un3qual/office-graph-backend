# PR 12 Review Fixes Design

## Context

PR #12 adds the `/packets` workspace and currently has three unresolved bot
review threads. A thread-aware GitHub refresh and a raw comment/review audit
found no additional outside-diff or duplicate findings. Greptile's top-level
summary repeats its inline pagination finding; CodeRabbit's review summary
repeats its two inline findings.

The accepted `add-packets-route` OpenSpec change remains authoritative. These
repairs must preserve its route-owned product configuration, generic
product-vocabulary-free shared UI, Relay-owned packet state, and cursor-based
pagination.

## Finding Assessment

### Nullable cursor exposes a dead Next control

The finding is valid. `packetConnectionFromRelay` currently copies
`pageInfo.hasNextPage` even when `pageInfo.endCursor` is null. `loadNextPage`
then refuses to navigate because it has no cursor, leaving the UI with an
enabled Next button that silently does nothing.

The workflow boundary will normalize this inconsistent server state:
`hasNextPage` is true only when Relay reports another page and supplies a
non-null end cursor. `nextCursor` remains nullable. This keeps the connection
state internally coherent before it reaches `PacketList`.

### Product destinations are duplicated across route layouts

The finding is valid, but the suggested `src/ui` location would violate the
accepted product-vocabulary boundary. The destination descriptors will move to
`assets/app/routes/productNavigation.ts`, where product labels and paths remain
route-owned. `OperatorLayout` and `PacketsLayout` will import the same typed
`PRODUCT_DESTINATIONS` constant. The generic `NavRail` and `WorkspaceShell`
interfaces remain unchanged.

### Packet detail border bypasses the design token

The finding is valid. `.packet-detail-list div` will use
`var(--og-color-border)` instead of `#edf1f3`, matching the surrounding packet
rules and allowing future token changes to apply consistently.

## Regression Coverage

Implementation will follow test-first cycles:

1. Extend the packet workflow test with `hasNextPage: true` and
   `endCursor: null`; verify the normalized state disables forward pagination
   and a Next attempt does not issue another Relay request.
2. Add a route-navigation configuration test that imports
   `PRODUCT_DESTINATIONS` and verifies the preserved labels and routes. This
   test will fail until the shared route-owned module exists.
3. Extend the packet route stylesheet assertions to require
   `.packet-detail-list div` to use `var(--og-color-border)` and reject the
   hardcoded color.

Existing operator and packet route tests will continue to prove that both
layouts render the same links and active-route behavior.

## Verification and Review Follow-Through

After focused regression tests pass, run the repository's Nix-backed
`mix verify` gate, strict validation for `add-packets-route`, and
`git diff --check`. Commit and push the repairs to the existing
`codex/do-next-task` branch. Refresh thread-aware GitHub review state after the
push, loop on any newly actionable bot feedback, and reply in each addressed
inline thread with the fix commit and verification evidence.

## Non-Goals

- Do not add new packet behavior, API fields, dependencies, or UI abstractions.
- Do not move product labels into `assets/src/ui`.
- Do not alter pagination history, selection semantics, or error handling
  beyond preventing the unusable next-page state.
- Do not rename the already-published branch while PR #12 is open.
