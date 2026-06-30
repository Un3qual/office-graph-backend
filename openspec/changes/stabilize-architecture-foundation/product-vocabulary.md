# Product Vocabulary Spine

This note is the stabilization reference for API and UI naming. Backend storage
may keep infrastructure records, but default operator-facing projections should
translate those records into the small MVP spine.

## Canonical MVP Concepts

| Product concept | User-facing role | Backend records that may support it | Default API/UI posture |
| --- | --- | --- | --- |
| Signal | Messy inbound trigger from a person, integration, or system. | Raw archive, normalized intake event, external reference, graph item. | Show as Signal or inbox item; hide raw archive details unless in trace/debug. |
| Work Item | Triaged unit of intended work or review. | Task, review finding, graph item, relationships, revisions. | Show as Work Item when the operator is deciding what work exists. |
| Work Packet | Bounded execution contract for a human or agent. | Work packet, packet version, source reference, required checks. | Show as Work Packet; treat handoff/package generation as packet state, not a separate product noun. |
| Run | Attempt to execute a Work Packet. | Run, run required checks, run events. | Show as Run; keep run events as trace/audit unless the operator acts on them. |
| Check | Condition that must be satisfied. | Verification check, required check. | Show as Check with state, blockers, and required evidence. |
| Evidence | Proof, counterproof, or missing proof for a Check. | Evidence item, evidence candidate, observation, missing evidence. | Show suggested, accepted, rejected, stale, or missing Evidence states; do not expose EvidenceCandidate as the default noun. |
| Verification | Decision over Checks and Evidence. | Verification result, check satisfaction, recomputation records. | Show Verification decisions/outcome; keep verification-result rows as audit detail unless needed. |

## Deferred Or Internal Terms

- `ProposedGraphChange`, `GraphPatch`, and generic graph mutation proposals are
  deferred from current MVP vocabulary. Legacy storage remains compatibility
  input only. Future ChangeProposal work must propose typed domain command
  input and apply through the owning domain command.
- Execution observations, operation correlations, graph items, graph
  relationships, revisions, run events, raw archives, policy bundles, and
  verification result rows are infrastructure records by default.
- Evidence-candidate storage may remain for provenance, replay, or migration,
  but API/UI projections should present it as suggested Evidence unless a later
  accepted workflow creates a dedicated evidence-review queue.
- Questions, decisions, rich text quote snapshots, SCIM group mappings,
  explicit grants, agent executions, graph conversations, and provider-specific
  review objects require workflow justification before becoming first-screen
  product vocabulary.

## API And UI Planning Rules

- Product frontend reads should use GraphQL projection clients that normalize
  transport shape into product-spine view models.
- JSON operator workflow routes are a temporary bridge; labels and UI copy
  still translate legacy field names into product-spine terms.
- Infrastructure detail belongs behind trace, audit, or debug fields with
  explicit authorization filtering.
- Command affordances should come from backend projections. The frontend should
  not infer product actions from raw graph relationships or infrastructure
  resource names.

## Proposal Checklist

Before promoting a non-spine concept into user-facing API or UI scope, the
proposal must identify:

- the workflow and operator action that require the concept;
- the projection contract and normalized product labels;
- authorization and trace/debug boundaries;
- why Signal, Work Item, Work Packet, Run, Check, Evidence, and Verification
  are insufficient;
- whether the concept is durable product vocabulary, a temporary compatibility
  bridge, or audit/debug detail.
