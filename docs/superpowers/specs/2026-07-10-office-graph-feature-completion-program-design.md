# Office Graph Feature Completion Program Design

date: 2026-07-10
status: approved
program branch: `codex/close-completed-changes`

## Outcome

Deliver the first feature-complete Office Graph product loop for the accepted
software review, fix, and verification workflow:

```text
GitHub review or check signal
  -> authorized intake and normalization
  -> operator clarification and packet creation
  -> governed human or internal-agent run
  -> observations and evidence
  -> verification decision
  -> GitHub follow-up
  -> reusable, auditable Office Graph history
```

Feature complete means a signed-in operator can execute this loop through
product UI and supported APIs without seeds, direct Elixir calls, database
edits, or hidden compatibility routes. It does not mean Office Graph replaces
GitHub, Jira, an IDE, CI runners, or every department workflow.

The program preserves the fixed React, Relay, Phoenix, Ash, Postgres, GraphQL,
JSON API, Boundary, Nix, and no-Tailwind constraints in `openspec/project.md`.

## Delivery Strategy

Use dependency-ordered vertical slices. Every product PR must leave a usable,
tested behavior; shared infrastructure is introduced only by the first slice
that consumes it. Do not combine the program into one branch or one PR.

Three approaches were considered:

1. **One feature-completion branch.** Rejected because the diff would combine
   identity, queues, integrations, agents, realtime, and UI behavior and would
   be too large to review, revert, or diagnose safely.
2. **Horizontal platform branches.** Rejected as the primary structure because
   standalone backend, frontend, realtime, and authorization projects would
   create long-lived infrastructure without a demonstrable product outcome.
3. **Dependency-ordered vertical slices.** Selected because each PR proves a
   user or operator capability while keeping domain boundaries explicit.

Each implementation branch owns exactly one active OpenSpec change. Planning
artifacts, code, tests, schema changes, and durable spec synchronization for
that capability travel together. Completed changes are archived only after
their branch passes verification.

## Branch And Pull Request Graph

```text
origin/main
  |
  +-- PR 1  codex/close-completed-changes
  |          archive the three complete OpenSpec changes
  |          add the accepted feature-completion program
  |
  +-- PR 2  codex/operator-command-loop
  |          manual intake + clarification + packet/run/evidence commands
  |
  +-- PR 3  codex/durable-work-delivery
  |          Oban jobs + typed domain events + authorized realtime invalidation
  |
  +-- PR 4  codex/identity-governance-admin
  |          login/session + external identity + roles/groups/grants/settings
  |
  +-- PR 5  codex/github-review-integration
  |          depends on PRs 3 and 4
  |          installation + webhooks + sync + outbound review follow-up
  |
  +-- PR 6  codex/internal-agent-runtime
  |          depends on PRs 2, 3, and 4
  |          executions + context + tools + approvals + node conversation
  |
  +-- PR 7  codex/feature-complete-product-loop
             depends on PRs 2, 5, and 6
             run/entity/settings UI + end-to-end workflow + metrics
```

PRs 2, 3, and 4 start from `main` after PR 1 merges and may be reviewed in
parallel because they own different product boundaries. PR 5 starts only after
PRs 3 and 4 merge. PR 6 starts only after PRs 2, 3, and 4 merge. PR 7 is the
integration PR and starts from `main` after all dependencies merge.

No implementation PR remains permanently stacked on an unmerged feature
branch. A short-lived stacked branch is allowed only when its parent PR is
already approved and the child dependency is explicit in both PR descriptions.

## PR 1: Close Completed Work And Establish The Program

Archive the current complete changes in dependency order:

1. `add-packets-route`
2. `adopt-relay-suspense-hooks`
3. `eliminate-backend-query-fanout`

Sync their delta specs before archival. Validate all durable specs after the
last archive. Commit this program design and the per-PR execution plans on the
same branch so subsequent feature branches start from an agreed delivery map.

PR 1 changes no product behavior.

## PR 2: Operator Command Loop

Create OpenSpec change `complete-operator-command-loop`.

A user can submit manual intake, resolve required clarification, apply the
accepted work-graph proposal, create and version a packet, start a run, record
an observation, accept or reject evidence, and complete or waive verification
through explicit product commands.

GraphQL mutations are narrow domain commands rather than a larger one-shot
mutation. JSON API actions expose equivalent command behavior where required by
the accepted dual-API contract. Relay owns server mutation state and refreshes
the affected query records. The operator and packet routes show allowed actions,
validation failures, stale-command conflicts, and safe authorization errors.

The existing `execute_packet_run_verification` mutation remains only until the
new command sequence covers its current tests and callers; because the product
is unreleased, it is then removed rather than retained as a compatibility path.

Clarification and decision records are implemented only to the extent needed
to unblock the proving workflow. A separate question-queue route is not part of
this PR.

## PR 3: Durable Work Delivery And Realtime Invalidation

Create OpenSpec change `add-durable-work-delivery`.

Introduce Oban as the durable job owner for integration processing, agent work,
retries, and delayed verification. Add typed, post-commit domain events and one
authorized projection-invalidation contract shared by Absinthe subscriptions
and Phoenix Channels. Realtime payloads carry identity and version hints; Relay
still re-reads authoritative data.

The PR includes retry classification, idempotency keys, dead-job visibility,
telemetry, and a test worker path. It does not add a provider integration or
model invocation on its own.

## PR 4: Identity And Governance Administration

Create OpenSpec change `add-identity-governance-admin`.

Implement browser login and logout, authenticated sessions, external identity
reconciliation, lifecycle disablement, scoped role assignments, custom roles,
external group mappings, temporary grants, and credential metadata. The local
identity lab uses authentik OIDC plus deterministic fake SCIM fixtures as
already required by the project context.

Add a settings route for organization identity, roles, mappings, credentials,
and audit-visible authorization decisions. Secret values are never returned to
Relay or logged; product records retain only secret references and metadata.

The owner bootstrap remains a test and local-development fixture, not a
production request fallback.

## PR 5: GitHub Review Integration

Create OpenSpec change `add-github-review-integration`.

Implement GitHub App installation records, scoped credentials, webhook
verification, raw archive storage, replay-safe normalization, backfill/sync
jobs, provider-neutral repository/pull-request/review/check records, and typed
external references. Inbound review comments and check results become operator
signals. Outbound commands can post a review reply or status only after
authorization and autonomy checks.

Webhook receipt returns quickly after durable enqueue. Provider failures are
classified as retryable, terminal, authorization, or configuration failures and
are visible in integration health. Delivery IDs and provider object versions
prevent duplicate durable effects.

This PR does not push code or act as a general GitHub automation platform.

## PR 6: Internal Agent Runtime

Create OpenSpec change `implement-internal-agent-runtime`.

Implement agent definitions, agent executions, typed execution events,
authorized context packages, model requests, tool requests, approval gates,
context-expansion requests, retries, and output classification. Every execution
is linked to a parent run, principal, operation, selected graph context,
autonomy envelope, and policy result.

Model output is untrusted. Durable mutations pass through the same domain
commands introduced in PR 2. Tool calls execute through named adapters with
separate capability and credential checks. Agent-produced evidence begins as an
evidence candidate and cannot verify work without the owning verification
contract.

Add one node-scoped conversation experience for the proving workflow. It is a
run-aware operator tool, not a general chat product.

## PR 7: Feature-Complete Product Loop

Create OpenSpec change `complete-software-review-product-loop`.

Connect the preceding capabilities into finished routes and end-to-end tests:

- operator inbox and clarification actions;
- editable packet detail and version history;
- all-runs list and run detail with execution timeline and approvals;
- evidence and verification decisions;
- focused entity/external-reference context for the selected work;
- integration and credential health;
- node-scoped agent conversation;
- packet-backed verified-completion instrumentation.

The acceptance fixture starts with a signed GitHub webhook, runs through
operator and agent actions, records CI or review evidence, reaches verified
completion, and records the authorized GitHub follow-up. Tests use deterministic
provider and model fakes; optional hosted smoke tests do not gate normal local
verification.

Reports remain limited to the accepted MVP measures. Full graph editing,
general workflow building, mobile, marketplace, custom CI, and broad department
packs remain deferred.

## Data And Ownership Rules

- Owning domains perform writes through Ash actions or named Ecto bulk/replay
  operations already allowed by the architecture ledgers.
- Graph projections never become alternate sources of truth.
- Core records use relational, typed columns and extension tables. Raw provider
  payloads and model/tool payloads may use archive storage under the existing
  JSON policy.
- Every external write, agent tool action, approval, verification decision, and
  credential use has an operation correlation and authorization decision.
- Tenant, workspace, sensitivity, and relationship authorization apply to
  reads, mutations, background jobs, realtime delivery, and agent context.
- Query shape and batch behavior are tested for every list, sync, and fanout
  path whose cardinality grows.

## Error Handling And Recovery

- User input failures return field-specific errors without leaking internal or
  authorization details.
- Stale commands fail with a conflict and require an authoritative reread.
- Webhook and job handlers are idempotent and safe to replay.
- Retryable external or model failures use bounded backoff; terminal failures
  remain visible with a remediation reason.
- Realtime loss never loses state because reconnecting clients re-read the
  authoritative projection.
- Revoked identities, grants, installations, or credentials fail closed for new
  work while retaining historical provenance.
- Partial agent or integration failure cannot mark a run verified.

## Verification Strategy

Every PR uses test-driven development, focused red/green checks, strict OpenSpec
validation, `git diff --check`, and the project `mix verify` gate. Schema and
frontend changes also run migrations, generated GraphQL schema checks, Relay
compiler validation, TypeScript typecheck, Vitest, and production app-shell
build verification.

PR-specific acceptance tests prove authorization, tenancy, idempotency,
retries, audit correlation, and query-count behavior. PR 7 adds the complete
workflow test across webhook, job, API, Relay UI, agent runtime, evidence,
verification, and outbound provider action.

## Completion Criteria

The program is complete when:

1. all seven PRs are merged and their OpenSpec changes are archived;
2. no active OpenSpec change remains from the program;
3. a non-bootstrap user can complete the proving workflow through supported UI
   and APIs;
4. GitHub and model activity can be exercised with deterministic local fakes;
5. authorization and audit history explain every sensitive read and write;
6. background work survives process restart and safely retries;
7. Relay recovers from missed realtime events through authoritative reads;
8. the complete verification suite passes from the Nix shell; and
9. deferred product categories remain explicitly outside the release boundary.
