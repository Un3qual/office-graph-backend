## Method

Every tracked file under `docs/superpowers/**` was compared with the current
OpenSpec capabilities, archived OpenSpec changes, shipped implementation, and
the commit that last changed the file. A file is classified as:

- `canonical`: its still-valid outcome is already represented by current
  OpenSpec, an archived OpenSpec change, and shipped behavior;
- `obsolete`: it is execution narration, a completed review plan, or a product
  direction superseded by current OpenSpec and shipped behavior;
- `promote`: it contains a still-current normative decision absent from
  OpenSpec.

No file was classified `promote`. The review found no unique current normative
decision that needs to be copied out of the parallel planning tree.

## Reconciliation

| Parallel planning file | Class | Canonical or shipped evidence |
| --- | --- | --- |
| `plans/2026-07-12-project-quality-remediation.md` | canonical | Archived changes `harden-project-quality` and `remediate-project-quality-audit`; current `project-quality-gates` and `architecture-stabilization` capabilities |
| `plans/2026-07-13-internal-agent-runtime.md` | canonical | Archived change `implement-internal-agent-runtime`; current `agent-*`, `agent-runtime`, and `execution-*` capabilities |
| `plans/README.md` | obsolete | Describes the parallel plan lifecycle that this accepted change removes |
| `plans/archive/2026-06-20-ash-conformance-repair.md` | canonical | Archived change `repair-ash-model-conformance`; current `backend-model-ownership` and `ash-domain-boundaries` capabilities |
| `plans/archive/2026-06-21-repo-wide-ash-model-conformance.md` | canonical | Archived change `repair-ash-model-conformance`; current `backend-model-ownership`, `backend-architecture`, and `architecture-stabilization` capabilities |
| `plans/archive/2026-07-02-current-product-path-cleanup.md` | canonical | Archived changes `stabilize-architecture-foundation` and `rebuild-operator-frontend-foundation`; current `ash-api-surface`, `frontend-architecture`, and `operator-console` capabilities |
| `plans/archive/2026-07-09-office-graph-review-issues.md` | canonical | Archived changes `design-product-frontend-platform` and `harden-project-quality`; current `project-quality-gates`, `frontend-architecture`, and `operator-console` capabilities |
| `plans/archive/2026-07-09-remove-relay-type-aliases.md` | obsolete | Completed frontend cleanup whose resulting generated Relay contract is shipped and covered by current frontend verification |
| `plans/archive/2026-07-10-backend-query-fanout.md` | canonical | Archived change `eliminate-backend-query-fanout`; current `backend-query-efficiency` capability |
| `plans/archive/2026-07-10-close-completed-changes.md` | obsolete | One-time OpenSpec archival procedure; the referenced changes are already archived |
| `plans/archive/2026-07-10-operator-command-loop.md` | canonical | Archived change `complete-operator-command-loop`; current `operator-command-loop` capability |
| `plans/archive/2026-07-10-pr-12-review-fixes.md` | obsolete | Completed pull-request review narration; behavior is shipped and covered by frontend tests |
| `plans/archive/2026-07-10-relay-suspense-hooks.md` | canonical | Archived change `adopt-relay-suspense-hooks`; current `frontend-architecture` capability |
| `plans/archive/2026-07-12-durable-work-delivery.md` | canonical | Archived change `add-durable-work-delivery`; current `durable-work-delivery` and `realtime-delivery` capabilities |
| `plans/archive/2026-07-13-github-review-integration.md` | canonical | Archived change `add-github-review-integration`; current `github-review-integration` capability |
| `plans/archive/2026-07-13-typed-graph-relationships.md` | canonical | Archived change `implement-typed-graph-relationships`; current `graph-relationships` and `typed-relationship-registry` capabilities |
| `plans/archive/2026-07-14-github-review-followup.md` | obsolete | Completed review-fix narration; resulting retry behavior is shipped under the `github-review-integration` contract |
| `plans/archive/2026-07-15-github-review-boundary-hardening.md` | obsolete | Completed review-fix narration; resulting boundary behavior is shipped under the `github-review-integration` and operation contracts |
| `plans/archive/2026-07-15-github-review-consistency-followthrough.md` | obsolete | Completed review-fix narration; resulting reconciliation behavior is shipped and covered by integration tests |
| `plans/archive/2026-07-15-github-review-lifecycle-permissions.md` | obsolete | Completed review-fix narration; current permission and lifecycle behavior is represented by `github-review-integration` |
| `plans/archive/2026-07-15-github-review-replay-consistency-followthrough.md` | obsolete | Completed review-fix narration; replay requirements are represented by `github-review-integration` and `idempotency-and-replay` |
| `plans/archive/2026-07-15-github-review-resilience-followthrough.md` | obsolete | Completed review-fix narration; resulting failure behavior is shipped under `github-review-integration` |
| `plans/archive/2026-07-15-github-review-storage-boundary-followthrough.md` | obsolete | Completed review-fix narration; storage ownership is represented by `github-review-integration` and `provider-neutral-resources` |
| `plans/archive/2026-07-16-github-review-classification-replay-followthrough.md` | obsolete | Completed review-fix narration; classification and replay behavior is shipped under current integration contracts |
| `plans/archive/2026-07-16-github-review-reliability-followthrough.md` | obsolete | Completed review-fix narration; reliability behavior is shipped and covered by integration tests |
| `plans/archive/2026-07-16-github-review-storage-terminalization-followthrough.md` | obsolete | Completed review-fix narration; terminal failure behavior is shipped under the current integration contract |
| `plans/archive/2026-07-16-github-review-thread-scope-followthrough.md` | obsolete | Completed review-fix narration; thread scope behavior is shipped under the current integration contract |
| `plans/archive/2026-07-16-github-review-validation-followthrough.md` | obsolete | Completed review-fix narration; validation behavior is shipped under the current integration contract |
| `plans/archive/2026-07-23-all-runs-product-surface.md` | obsolete | Archived change `add-all-runs-product-surface`, subsequently narrowed by `simplify-product-native-runtime`; current run and operator capabilities are authoritative |
| `plans/archive/2026-07-23-openspec-product-boundary-correction.md` | canonical | Archived changes `implement-internal-agent-runtime` and `simplify-product-native-runtime`; current product-native runtime capabilities |
| `specs/2026-07-10-office-graph-feature-completion-program-design.md` | obsolete | Historical PR program; its delivered work is represented by archived changes and its remaining direction is superseded by current OpenSpec |
| `specs/2026-07-10-pr-12-review-fixes-design.md` | obsolete | Completed pull-request review design; resulting behavior is shipped and tested |
| `specs/2026-07-10-relay-suspense-hooks-design.md` | canonical | Archived change `adopt-relay-suspense-hooks`; current `frontend-architecture` capability |
| `specs/2026-07-13-typed-relationships-github-agent-program-design.md` | canonical | Archived changes `implement-typed-graph-relationships`, `add-github-review-integration`, and `implement-internal-agent-runtime`; current corresponding capabilities |
| `specs/2026-07-23-all-runs-product-surface-design.md` | obsolete | Archived change `add-all-runs-product-surface`, subsequently narrowed by `simplify-product-native-runtime` |
| `specs/2026-07-23-openspec-product-boundary-correction-design.md` | canonical | Archived change `simplify-product-native-runtime`; current product-native runtime capabilities |

## Outcome

The parallel tree contains duplicated canonical decisions and historical
execution evidence only. Removing it loses no current product or architecture
requirement. OpenSpec remains the sole durable source for every still-current
decision identified by this review.
