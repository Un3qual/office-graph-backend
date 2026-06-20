# Office Graph OpenSpec Plan Review

**Date:** 2026-06-20
**Reviewer:** Claude (Opus 4.8)
**Scope:** All six active OpenSpec changes plus `openspec/project.md` and
`openspec/project-plan.md`, reviewed before any application code is written.

---

## 1. What was reviewed

Six active changes (all pass `openspec validate --changes --strict` on OpenSpec
1.4.1):

| Change | Capabilities (specs) | Tasks done |
| --- | --- | --- |
| `define-office-graph-foundation` | foundation, work-graph, agent-runtime, authorization, verification, persistence, backend-architecture | 13/33 |
| `design-work-graph-core` | work-containers, graph-items, graph-relationships, graph-projections, domain-attachments, node-conversations | 15/29 |
| `design-persistence-model` | mvp-persistence-inventory, graph-storage-contract, provider-neutral-resources, extension-table-rules, external-reference-model, json-storage-policy, portable-rich-text-persistence, ordered-placement-model, tenant-scope-indexing, large-table-growth | 35/44 |
| `design-revision-audit-soft-delete` | typed-revision-history, audit-record-boundaries, operation-correlation, soft-delete-tombstones, retention-legal-hold-export | 23/28 |
| `design-enterprise-governance` | tenancy, authorization-governance, audit-compliance, credential-security, ai-data-controls, enterprise-integration-posture, run-approval-governance | 25/32 |
| `design-code-organization-and-boundaries` | bounded-context-architecture, ash-domain-boundaries, ecto-sql-boundaries, boundary-enforcement, shared-operation-contracts, extractable-library-boundaries, entrypoint-boundary-contracts | 4/34 |

Plus the seven follow-on changes that are **referenced but not yet written**:
`design-ingestion-and-integrations`, `design-agent-runtime`,
`design-proposed-graph-changes`, `design-work-packets-and-readiness`,
`design-runs-and-verification`, `design-api-realtime-and-ui-projections`, and
(missing entirely) any identity/authentication change.

---

## 2. Overall assessment

This is unusually strong, internally consistent design work. A few principles
are applied with real discipline across every change and rarely contradict each
other:

- provider-neutral base tables before provider-specific extensions
- no JSON/JSONB for queryable product data
- **no polymorphic local `type` + `id` foreign keys** (concrete FKs to graph
  identity or typed domain tables)
- graph edges never grant access; every projection filters through authorization
- typed, aggregate-aware revisions instead of one universal `versions` blob
- operation correlation as a shared write trace instead of a single event table
- explicit deferral of implementation (every change is design-only and says so)

The risks below are **not** "this is wrong." They are mostly **coherence,
coverage, and sequencing** risks created by authoring six large interlocking
design changes in parallel, plus a few **scope/MVP-size** risks. The single most
important theme: the plans are detailed enough that the gaps between them, and a
few load-bearing deferrals, are now the main danger — not the individual
decisions.

The recommendations in §9 are the actionable distillation.

---

## 3. Findings summary (prioritized)

| # | Severity | Finding |
| --- | --- | --- |
| F1 | **Critical** | No change inventories the authorization/identity/credential **tables** (principals, roles, role assignments, capabilities, custom roles, grants, scopes + scope hierarchy, memberships, classifications, policy bundles, external identity links, credential metadata). Governance designs them conceptually but is "no tables"; persistence omits them. |
| F2 | **Critical** | No identity/authentication design change exists or is planned, yet everything assumes principals, sessions, SSO/SCIM reconciliation, service-account/agent credentials, and account-linking. It is also a named library-extraction candidate. |
| F3 | **High** | The "immediate MVP migration cut" can store proving-workflow data but cannot **run** the core loop: runs, run events, verification state, work packets, and proposed graph changes are all deferred. The MVP wedge (software review/fix/**verification**) is not executable from the first schema. |
| F4 | **High** | Duplicate / competing canonical requirements across active changes: `Unified Principal Model` (foundation + governance), `Audit Record Shape` (governance + revision-audit), operation-correlation specified 4×, edges-don't-grant-access 5×, agent-permission formula with drifting arity. No reconciliation/ownership plan for promotion to durable `specs/`. |
| F5 | **High** | Capability taxonomy collision on promotion: foundation defines coarse capabilities (`authorization`, `persistence`, `work-graph`, `agent-runtime`, `verification`, `backend-architecture`) that the detailed changes re-cover with finer capabilities. No decision on whether foundation's coarse specs get promoted, and if so how they coexist. |
| F6 | **High** | Sequencing inversion: `project-plan.md` lists `design-enterprise-governance` last (#12), but `design-work-graph-core` (#2) and `design-persistence-model` (#3) explicitly depend on governance decisions (org-root tenancy, scopes, edges-don't-grant). The stated discovery/sequencing order is now misleading. |
| F7 | **High** | Scope/cost: the first migration cut is ~50–70 tables and includes a full **copy-on-write portable rich-text subsystem** (versioned blocks/inlines/marks, pinned vs live quotes with snapshot hashes, selection-intent preservation) and a fractional-indexed ordered-placement system. Each is a multi-month effort and arguably a product in itself, front-loaded before a running slice exists. |
| F8 | **Medium** | The product wedge is still undecided (first buyer, first daily user, flagship metric, first intake source remain open in foundation tasks §3 and project-plan "First Question To Answer"), while ~50 tables of persistence are fully specified. Risk of deep schema design ahead of wedge validation. |
| F9 | **Medium** | `check` is overloaded across three distinct concepts: verification checks, approval gates ("approvals are checks"), and provider `check_runs` (CI). Needs disambiguation before it reaches the schema/API. |
| F10 | **Medium** | Classification enum mixes **visibility scope** (`workspace_scoped`, `project_scoped`, `team_restricted`) with **sensitivity** (`secret`, `source_code`, `finance_sensitive`). Conflating these in one label will muddle policy and redaction logic. |
| F11 | **Medium** | Rich-text revisions and aggregate (`typed-revision-history`) revisions are two revision systems; the boundary (what is a "task revision" vs a "rich-text revision") and how reconstruction stitches them via operation correlation is underspecified. |
| F12 | **Medium** | Ingestion semantics (webhook → signal, idempotency, ordering, sync state machine, adapter contract) are deferred, but ingestion **is** the MVP proving workflow. The proving tables exist with no design for how they get populated. |
| F13 | **Medium** | A stated MVP deliverable — basic custom-role frontend UI + endpoints — has no design home (frontend not started, no API/UI change, governance is design-only). |
| F14 | **Low** | Graph relationships/edges are absent from the "first tombstone shapes" list; edge soft-delete/restore and cascade-on-node-delete semantics are unspecified. Restore cascade for parent→children (e.g., restore initiative → its tasks) is also unspecified. |
| F15 | **Low** | `define-office-graph-foundation` lacks the `.openspec.yaml` metadata file the other five have; its tasks list is the most stale (open questions answered downstream remain unchecked). |
| F16 | **Low** | Column-name wavering: governance writes "`initiative_id` or `project_id`." Lock one column name (`initiative_id`) with "project" as display alias only. |
| F17 | **Low** | `audit_event_details` constrained-JSONB exception (revision-audit) reads as contradicting the absolutist JSON-avoidance spec (foundation/persistence). They are reconcilable but should cross-reference each other. |

---

## 4. Critical findings (address before writing code)

### F1 — The authorization/identity data model is designed in prose but inventoried nowhere

`design-enterprise-governance` is the most detailed change, but it is explicitly
**design-only with no table list** (Non-Goals: "No final table list for every
governance record"). `design-persistence-model` calls itself "the concrete MVP
persistence inventory" — yet its first-class inventory (`design.md` decision 2;
`mvp-persistence-inventory/spec.md`) lists organizations, workspaces,
initiatives, workstreams, graph items/relationships, the work-loop resources,
conversations, rich text, ordered placement, external references, raw archives,
and operation correlation. A grep confirms **none** of these appear as
inventoried resources or in the immediate migration cut (§14):

- principals / users
- roles, role assignments, capabilities, custom roles
- grants
- **scopes and the scope-hierarchy / closure table** (the backbone of the
  hierarchical-inheritance authorization model)
- teams, components, repositories-as-scopes, departments, org units
- memberships
- classifications (as stored rows)
- policy bundles / policy versions
- external identity links
- credential metadata / secret references

`design-revision-audit-soft-delete` does inventory `audit_events`,
`audit_event_targets`, `audit_event_details`, the audit action registry,
authorization decision records, operation correlation, and tombstones — so the
*audit/decision* side is covered. But the **policy fact** tables that the entire
governance model interprets are owned by no change.

**Why it matters:** authorization is declared a core bounded context and the
first thing every Ash policy will call. You cannot build the first resource with
policies without principals, scopes, role assignments, capabilities, grants, and
the scope tree. This is the most concrete blocker to "start writing code."

**Recommendation:** add a persistence inventory + migration-cut entry for the
governance/identity tables — either by extending `design-persistence-model`
(preferred, since it owns "the concrete inventory") or by adding a dedicated
`design-identity-and-authorization-schema` change. Decide the scope-tree storage
representation explicitly (adjacency list + closure table vs `ltree` vs
materialized path), because hierarchical scope inheritance is security-critical
and hard to change later.

### F2 — There is no identity/authentication design change

The foundation's follow-on list and `project-plan.md`'s "Proposed First Formal
OpenSpec Changes" (1–12) contain **no** identity/auth change. Yet:

- `design-code-organization-and-boundaries` lists "identity and authentication"
  as logical context #1 and a library-extraction candidate.
- `design-enterprise-governance` assumes SSO/OIDC/SAML reconciliation, SCIM
  provisioning, external identity links, account-linking policy, service
  accounts, webhook-source principals, and agent principals.

What is missing is the actual **authentication mechanics and identity data
model**: human session/token model, how a `principal` is created and
authenticated, service-account credential issuance, agent principal credentials,
the external-identity-link table, and the bootstrap/first-admin path. Governance
covers *posture* (SSO/SCIM should map into internal roles) but not *mechanics*.

**Recommendation:** add `design-identity-and-authentication` (or fold it into
the F1 schema change) before code generation. Treat it as a library-extraction
candidate from the start, per the existing extractability rules.

---

## 5. High-severity findings

### F3 — The first migration cut cannot execute the core loop

`design-persistence-model` §14 ("Immediate MVP migration scope") deliberately
**excludes** work packets, runs, run events, proposed graph changes, context
expansion requests, final revision/audit/tombstone structures, and projection
read models. It **includes** review comments, review findings, checks, evidence,
and the software proving tables.

So the first schema can *store* imported review/CI/Sentry data, but it cannot run
the differentiating loop the foundation defines:

```
signal → … → work packet → human/agent/integration run → evidence → verification
```

Runs, verification state, work packets, and the proposed-graph-change mechanism
are all in the deferred set. This may be intentional (a static data foundation
first), but the plans don't say so plainly, and it's easy to read the "software
proving workflow" as runnable from the first migration.

**Recommendation:** state explicitly that the first migration is a **static
data + ingestion foundation**, not a runnable proving workflow — *or* pull the
reserved execution resources (runs, run events, verification, a minimal proposed
graph change) forward into the first cut so a thin vertical slice can actually
execute end-to-end. See the walking-skeleton recommendation in §9.

### F4 — Duplicate and drifting requirements across active changes

Because all six changes are authored as `## ADDED Requirements` against an empty
`openspec/specs/`, several real-world concepts are specified more than once, with
no `MODIFIED` relationship and no statement of which change is canonical:

- **`Requirement: Unified Principal Model`** appears verbatim-titled in both
  `define-office-graph-foundation/specs/authorization/spec.md` and
  `design-enterprise-governance/specs/authorization-governance/spec.md`.
- **`Requirement: Audit Record Shape`** appears in both
  `design-enterprise-governance/specs/audit-compliance/spec.md` and (with a
  richer, partly different envelope) `design-revision-audit-soft-delete/specs/
  audit-record-boundaries/spec.md`.
- **Operation correlation** is specified in four changes (persistence §11/§17,
  revision-audit `operation-correlation`, governance `audit-compliance`, code-org
  `shared-operation-contracts`) with **four slightly different field lists** —
  compatible but not identical.
- **Edges-don't-grant-access** is restated in ≥5 places (foundation work-graph +
  authorization, work-graph graph-relationships + graph-projections, governance
  tenancy).
- **Agent effective-permission formula drift:** foundation/authorization defines
  a 5-term intersection; `governance/design.md` adds a 6th
  (`resource classification policy`); `authorization-governance/spec.md` adds
  context-expansion / temporary-grant terms. Three arities for one formula.

**Why it matters:** when these changes are archived into `openspec/specs/`, two
near-duplicate canonical requirements either collide (same capability) or create
"which spec is authoritative?" ambiguity (different capabilities). The drift in
the permission formula is the kind of thing that produces subtly different policy
code in different places.

**Recommendation:** before promotion, designate **one** canonical owner per
shared concept (principal model, audit record shape, operation correlation,
permission formula, edges-don't-grant). Have the foundation's lighter versions
explicitly point to the governance/revision-audit canonical version, or strip
them from foundation. Pin the operation-correlation field list and the
permission formula in exactly one place and reference it everywhere else.

### F5 — Capability taxonomy will collide on promotion

Foundation creates coarse capabilities (`authorization`, `persistence`,
`work-graph`, `agent-runtime`, `verification`, `backend-architecture`,
`foundation`). The detailed changes create finer ones that cover the same ground
(`authorization-governance`/`tenancy`/`audit-compliance`,
`mvp-persistence-inventory`/`graph-storage-contract`/…, `work-containers`/
`graph-items`/…). Archiving foundation would create `specs/authorization/`,
`specs/persistence/`, etc., *and* archiving the detailed changes would create the
parallel granular capabilities — leaving both coarse and fine specs for the same
domains.

**Recommendation:** decide now whether `define-office-graph-foundation` is
(a) a framing/proposal change whose deltas are **not** promoted to durable specs
(it stays as the "why/what" record), or (b) promoted as intentionally
high-level "umbrella intent" specs that the granular capabilities refine. Option
(a) is cleaner. Either way, record the canonical capability map (the durable
`specs/` layout) as an explicit artifact so each change knows where its
requirements land.

### F6 — Stated sequencing contradicts real dependencies

`project-plan.md` ("Proposed First Formal OpenSpec Changes" and "Suggested
Discussion Order") puts `design-enterprise-governance` at #12 (last). But
`design-work-graph-core/design.md` opens by consuming governance decisions ("The
enterprise governance design defines organization as the root tenant, workspace
plus initiative/project as default scopes…"), and `design-persistence-model`
depends on both. The actual authoring DAG is roughly:

```
foundation
  → enterprise-governance
    → work-graph-core
      → persistence-model
        → revision-audit-soft-delete
          → code-organization-and-boundaries
```

**Recommendation:** update `project-plan.md` to reflect the real dependency
order (governance early, not last), or add a short "actual dependency DAG"
note. Otherwise anyone following the plan's discussion order hits forward
references. The plan is also now partly historical (several "Not yet locked"
items are locked downstream) — add pointers from each discovery track to the
change that resolved it.

### F7 — The portable rich-text + ordered-placement subsystem is enormous for a first cut

`design-persistence-model` decisions 12, 13, 16 and the
`portable-rich-text-persistence` / `ordered-placement-model` specs describe:

- `rich_text_documents` + semantic `rich_text_document_revisions`
- stable `rich_text_blocks` + versioned `rich_text_block_versions`
- stable `rich_text_inlines` + versioned `rich_text_inline_versions`
- `rich_text_mark_types` + versioned `rich_text_inline_mark_versions`
- typed reference tables, sidecar anchor/range/quote-snapshot tables
- derived render caches (plain text, HTML, agent Markdown, Lexical adapter)
- copy-on-write reconstruction via validity ranges
- pinned quotes (snapshot + hash + source revision) vs live references
  (resolution status: resolved/stale/deleted/ambiguous/unauthorized/reordered)
- selection-intent preservation across source reorders
- a fractional lexicographic position-key system with rebalancing and
  optimistic-concurrency conflict handling

This is genuinely excellent design, but it is **a product in itself**, and it is
in the *first* migration cut. The plan's own JSON-avoidance rule explicitly
forbids the usual pragmatic shortcut (persist editor JSON behind an adapter,
normalize later), which front-loads the entire cost.

**Recommendation:** explicitly revisit whether full copy-on-write rich text and
the generic ordered-placement contract must be in the first migration, or whether
MVP can ship a **constrained typed body model** (blocks + marks + typed
references, with whole-document revisions rather than per-inline copy-on-write)
and promote to the full model once the editor and real usage exist. Consider a
spike to validate the fractional-key + copy-on-write reconstruction design before
committing it to the foundational migration. This single decision probably moves
the MVP date more than any other.

---

## 6. Medium-severity findings

### F8 — Product wedge is undecided while schema is fully specified

Foundation tasks §3 still has these **unchecked**: first buyer, first daily user,
flagship success metric, and first intake source. `project-plan.md`'s "First
Question To Answer" (which concrete proving workflow / buyer / metric) is open.
Meanwhile ~50 tables are specified in detail. The deep persistence work is
defensible (the *foundation* should outlast wedge choices), but the highest
product risk — "does Office-Graph-compiled work beat baseline agent use in one
concrete workflow?" — is unvalidated. Make sure schema depth isn't standing in
for wedge validation. (Foundation tasks §3 also lists several questions that are
in fact answered downstream — tenancy scopes, role vocab, durable-decision
policy, JSON locations, revision pattern — so that list reads as more open than
it is; refresh it.)

### F9 — `check` is three different concepts

- verification check — "something that must be true" (`foundation/verification`)
- approval gate — "approvals are checks with evidence" (`governance/run-approval-governance`)
- provider `check_run` — CI check (`persistence` software proving inventory)

**Recommendation:** disambiguate explicitly. Likely: keep `check` for the
verification concept, name approval gates `approval_gate` (a related but distinct
record that may *produce* a check/evidence), and keep `check_run` clearly as the
provider-neutral CI resource. State the relationships before they reach the API.

### F10 — Classification mixes scope and sensitivity

Governance decision 9 / `authorization-governance` list one classification enum
containing both visibility-scope values (`org_internal`, `workspace_scoped`,
`project_scoped`, `team_restricted`) and sensitivity values (`secret`,
`source_code`, `customer_sensitive`, `finance_sensitive`, `legal_sensitive`,
`security_sensitive`). Visibility scope is largely derivable from the scope
columns; sensitivity is an orthogonal label that drives redaction, AI-provider
eligibility, and export approval.

**Recommendation:** separate "visibility scope" (from scope columns) from
"sensitivity classification" (orthogonal typed label). Collapsing them invites
ambiguous rows (a `source_code` artifact that is also `team_restricted`).

### F11 — Two revision systems, fuzzy boundary

`typed-revision-history` says aggregate revisions "MUST link to the rich text
revision … without creating unrelated content revisions" — good. But a `task`
has rich-text fields *and* scalar fields. The rule for "what counts as a task
revision vs a rich-text-document revision," how both link to the same operation
correlation record, and how reconstruction stitches them is not stated.

**Recommendation:** add an explicit decision: aggregate revisions capture scalar
field changes and *reference* the owning rich-text document revision id for body
changes; both share the operation id; reconstruction composes them. Worth a
worked example (e.g., "user edits a task title and one word of its description in
one save").

### F12 — Ingestion is deferred but is the MVP

The proving workflow is fundamentally ingestion (import PR comments / CI / Sentry
→ findings → fix → verify). Persistence includes the proving tables and external
sources/references/raw archives; governance covers webhook-source principals and
credentials. But idempotency, out-of-order/duplicate webhook handling, sync
state machine, and the adapter contract live in the unwritten
`design-ingestion-and-integrations`. So the first migration has the *tables* but
not the *semantics* that populate them.

**Recommendation:** sequence `design-ingestion-and-integrations` immediately
after the identity/authz schema gap is closed, and before the first code cut that
claims to demo the proving workflow.

### F13 — A stated MVP UI deliverable has no design home

`project.md` and governance's resolved questions both say MVP includes a basic
custom-role frontend UI plus backend endpoints. But frontend hasn't started,
there is no frontend/`design-api-realtime-and-ui-projections` change yet, and
governance is design-only.

**Recommendation:** either descope the custom-role *UI* from MVP (keep schema +
endpoints + tests, defer UI), or note that it depends on the API/UI projection
change landing first. Don't leave a UI deliverable floating without a design.

---

## 7. Low-severity findings / nits

- **F14 — Edge tombstones & restore cascade.** `soft-delete-tombstones`'s "first
  tombstone shapes" lists graph items, work containers, conversations, messages,
  provider-neutral records, and artifacts — **not** graph relationships/edges,
  which are also deletable and need restore semantics. Cascade behavior
  (restoring an initiative → its tasks; deleting a node → its edges) is
  unspecified. Add edge lifecycle to the tombstone/restore design.
- **F15 — Foundation metadata/staleness.** `define-office-graph-foundation` has
  no `.openspec.yaml` (the other five have `created: 2026-06-18`) and the most
  unchecked tasks. Validation still passes, so it's cosmetic — but add the
  metadata and refresh its open-questions list.
- **F16 — Lock the column name.** Governance writes "`initiative_id` or
  `project_id`." Pick `initiative_id`; "project" is a display alias only (as
  already decided elsewhere).
- **F17 — JSON-policy cross-reference.** The sanctioned `audit_event_details`
  constrained-JSONB exception should cross-reference `json-storage-policy` so the
  two don't read as contradictory once promoted. (The audit design handles it
  correctly — typed envelope + relational targets + schema-versioned details with
  "queryable fields must not live only in details" — it just needs an explicit
  link.)
- **Process nit.** `design-code-organization-and-boundaries` has its review tasks
  (§1, §2) entirely unchecked while validation (§5) is checked — i.e., validated
  but not reviewed. Worth completing the review pass since it's the change that
  gates the first code generation.

---

## 8. What is strong (keep doing this)

- The **no-polymorphic-FK** rule (concrete FKs to graph identity or typed tables,
  with the narrow external-reference exception) is consistently applied and will
  save real pain in Postgres/Ash.
- **Concern separation** (revisions ≠ audit ≠ authorization decisions ≠ domain
  events ≠ run events ≠ sync events ≠ raw archives) is articulated clearly and
  repeatedly, with operation correlation as the join.
- **Provider-neutral-first** with extension-table escape hatches, plus the
  review-comments-vs-review-findings split, shows the ontology is being kept
  department-neutral under real pressure from the software workflow.
- The **audit envelope/targets/versioned-details** model is a mature design that
  balances SIEM/export needs against typed storage.
- **Soft-delete-aware uniqueness** (partial indexes for reusable display names;
  permanent reservation for URL slugs/handles; per-org/source/object provider-id
  reservation) is exactly the level of rigor that prevents URL-hijack and
  reconciliation bugs.
- Deferrals are explicit and the dependency hand-offs between changes are written
  down (each change's "Follow-On Planning Work" feeds named successors).

---

## 9. Recommended actions before writing code

Ordered roughly by leverage:

1. **Close the authz/identity schema gap (F1, F2).** Add the
   principal/role/capability/grant/scope-tree/membership/classification/policy-
   bundle/external-identity/credential inventory and a scope-hierarchy storage
   decision — either by extending `design-persistence-model` or adding
   `design-identity-and-authorization-schema`. Add a
   `design-identity-and-authentication` change for auth mechanics.

2. **Decide the durable capability map and promotion policy (F4, F5).** Pick one
   canonical owner per shared concept; decide whether foundation's coarse specs
   are promoted at all; pin the operation-correlation field list and the agent
   permission formula in exactly one place.

3. **Define a "walking skeleton" vertical slice (F3, F7, F8).** One thin path —
   one signal → one task → one finding → one check → one evidence → verified —
   with auth, one audit record, and one revision, using a *constrained* body
   model rather than full copy-on-write rich text. Let it pressure-test the
   boundaries before committing all ~50 tables and the rich-text subsystem. This
   also surfaces whether the wedge actually delivers value.

4. **Re-scope rich text and ordered placement for v1 (F7).** Explicitly choose
   "full copy-on-write now" vs "constrained typed body + whole-doc revisions now,
   promote later," ideally after a spike on the fractional-key + reconstruction
   design.

5. **Sequence the missing changes (F6, F12).** Update `project-plan.md` ordering;
   write `design-ingestion-and-integrations` and `design-proposed-graph-changes`
   (the latter underpins the entire "agents propose, domain actions decide"
   safety model and touches persistence/authz/revisions/audit/runtime at once) —
   before any code claims the proving workflow.

6. **Resolve the modeling ambiguities (F9, F10, F11, F16).** Disambiguate
   `check`; split visibility-scope from sensitivity-classification; specify the
   aggregate-vs-rich-text revision boundary with a worked example; lock
   `initiative_id`.

7. **Tidy (F13, F14, F15, F17).** Give the custom-role UI a home or descope it;
   add edge tombstone/restore + cascade rules; add foundation's `.openspec.yaml`
   and refresh its stale task list; cross-link the JSON exception.

---

## 10. Validation evidence

```
OpenSpec 1.4.1 (via project Nix flake)
$ openspec validate --changes --strict
✓ change/define-office-graph-foundation
✓ change/design-code-organization-and-boundaries
✓ change/design-enterprise-governance
✓ change/design-persistence-model
✓ change/design-revision-audit-soft-delete
✓ change/design-work-graph-core
Totals: 6 passed, 0 failed (6 items)
```

All findings above are design-coherence / coverage / sequencing issues, not
schema-validation failures.
