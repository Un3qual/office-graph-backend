## 1. Design Acceptance

- [x] 1.1 Confirm this change is design-only and does not implement storage,
  APIs, runtime behavior, verification engines, provider adapters, or UI.
- [x] 1.2 Confirm work runs are parent executions of selected work, distinct
  from individual agent executions.
- [x] 1.3 Confirm agent executions are child runtime invocations that may be
  one of several activities inside a work run.
- [x] 1.4 Confirm work runs can coordinate mixed child activity, including
  agent executions, human handoffs, external observations, change proposals,
  checks, evidence, approvals, waivers, revisions, and audit records.
- [x] 1.5 Confirm verification is check/evidence based rather than derived
  from successful work-run, agent-execution, provider, or human status alone.
- [x] 1.6 Confirm `change_proposal` is the locked vocabulary for untrusted
  proposed domain actions; `proposed_graph_change` is retired as product
  language and any implementation rename is separate work.

## 2. Capability Spec Review

- [x] 2.1 Review `work-runs`.
- [x] 2.2 Review `agent-executions`.
- [x] 2.3 Review `execution-observations`.
- [x] 2.4 Review `verification-evidence`.

## 3. Cross-Change Handoff

- [x] 3.1 Align the dedicated change-proposal design with the locked
  `change_proposal` terminology.
- [x] 3.2 Propagate change-proposal terminology into active OpenSpec changes
  that reference the mutation-safety model.
- [x] 3.3 Preserve existing code/table/module identifiers as implementation
  details until an explicit implementation rename is planned.

## 4. Validation

- [x] 4.1 Run `openspec validate design-runs-and-verification --strict`.
- [x] 4.2 Run `openspec validate design-proposed-graph-changes --strict`.
- [x] 4.3 Run `openspec validate --changes --strict`.
