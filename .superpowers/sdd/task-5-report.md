# Task 5 Report: Frontend Correctness And Accessibility

Status: **DONE**

## Delivered

- Relay network execution is Observable-backed. Disposing query or mutation subscriptions aborts the underlying HTTP request, clears timeout/listener resources, and prevents late success or error delivery.
- Command failures retain every safe field error. Snake-case server fields map to camel-case form controls, all errors appear in a visible alert summary, editable controls receive inline feedback plus `aria-invalid`/`aria-describedby`, and the first mapped invalid control receives focus.
- Internal run navigation uses React Router. Relay maps `DateTime` to `string`, generated artifacts reflect that type, fragment reads use explicit generics instead of blind casts, and packet/evidence copy uses current product vocabulary.
- Repository caller evidence proved the operator-only start-run document/hook/test/artifact had no production caller; the packet-owned start-run path remains. The dead path, StyleX runtime/plugin/config/transforms, and legacy style aliases are removed.
- Shared-UI dependency checks use the TypeScript AST and cover static imports, dynamic imports, import-equals declarations, re-exports, and Relay `graphql` tags without matching comments.
- Exact Biome `2.2.4` provides source-scoped lint and format checks. Verification covers 85 handwritten frontend files while Relay artifacts, build output, router type output, and dependencies are excluded.

## TDD Evidence

- Cancellation RED: `executeGraphQL` did not exist; disposal could not abort fetch. GREEN: focused Relay tests 10/10 and typecheck.
- Accessibility RED: the two-field packet mutation response rendered only the first error with no focus or ARIA mapping. GREEN: the integration regression verifies both summary messages, inline descriptions, invalid state, and first-control focus.
- Navigation/scalar/copy RED: run links lacked Router discovery, `DateTime` generated as `any`, and UI exposed stale queue/internal evidence-candidate wording. GREEN: focused Relay/navigation/operator tests 9/9 and typecheck.
- Cleanup/tooling RED: the unused operator mutation path, StyleX dependencies/transforms, old CSS aliases, and missing lint/format scripts were all detected. GREEN: focused static/dead-code/command tests 24/24.
- Full-suite diagnosis found one stale token assertion expecting `versions` after the accepted paged field became `versionHistory`; the focused regression passed after correcting the expected compiled-query contract.

## Final Verification

Executed inside the pinned Nix shell:

- `pnpm run relay:check`: 22 reader, 17 normalization, 22 operation-text documents valid.
- `pnpm run typecheck`: passed.
- `pnpm run lint`: 85 files checked, no findings.
- `pnpm run format:check`: 85 files checked, no changes required.
- AST/import-boundary gate: 15/15 tests passed.
- Full Vitest: 142/142 tests passed across 21 files.
- React Router production client and SSR builds: passed; app-shell asset verification passed.
- `openspec validate harden-project-quality --strict`: passed before checklist update and scheduled again for final handoff.
- `git diff --check`: clean before checklist/report update and scheduled again for final handoff.

## Commits

- `a2ea487` — cancel disposed Relay requests
- `adc493b` — accessible complete command field errors
- `b711528` — client navigation, scalar typing, safe copy, and typed Relay reads
- `447fad3` — dead frontend/StyleX cleanup, AST boundaries, and static tooling
- `4c2f826` — align the compiled-query test with paged packet history

## Self-review

- Confirmed the retained packet start-run hook has a production caller and the removed operator variant does not.
- Confirmed no StyleX imports or package entries remain outside negative regression assertions.
- Confirmed the Observable guard suppresses both late payload and late error delivery after disposal.
- Confirmed projection-owned, non-editable field errors remain visible in the complete summary even when no user control can receive inline feedback or focus.
- No browser tools, Tailwind, shadcn, LiveView, backend organization files, or OpenSpec tasks outside 6.1-6.4 were changed.
