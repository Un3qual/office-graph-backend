## Context

The preceding branch delivered the canonical `run-review` runtime and the All
Runs product route, then accumulated defensive compatibility and test
infrastructure in response to hypothetical upgrade and architecture cases.
Office Graph is unreleased, OpenSpec is development-only, and the current
product behavior is already protected by authorization-aware backend and
route-level behavior tests.

## Goals / Non-Goals

**Goals:**

- Remove code that exists only for the invalid legacy definition or for testing
  custom test analyzers.
- Make URL selection and Relay the single owners of explicit selection and
  server data.
- Keep run indexing bounded, authorized, keyset-paginated, and limited to list
  fields.
- Preserve safe errors, retries, stale-detail clearing, worker recovery, and
  current run-review authority.
- Leave one concise OpenSpec record as the implementation source of truth.

**Non-Goals:**

- Changing agent execution, cancellation, leases, or invocation lock ordering.
- Replacing keyset pagination or independent list/detail error boundaries.
- Removing generated Relay artifacts, durable OpenSpec specifications, or
  archived OpenSpec history.
- Adding compatibility for a released database or external API consumer.

## Decisions

### Fresh-install history is authoritative

Delete the forward reconciliation migration and its upgrade-only tests. Keep
the corrected historical migrations that install `run-review`; local databases
created from the invalid history reset. This follows the existing unreleased
development policy and avoids maintaining a second upgrade lifecycle.

### Architecture checks inspect the repository, not an analyzer

Retain small tests that inspect the resolved route registration, actual imports,
actual stylesheet ownership, generated artifact placement, and dependency
manifest. Remove synthetic route/source fixtures, TypeScript expression
evaluation, custom module resolution, and shell/glob parsing.

### URLs own explicit selection

A present `runId` or `packetId` is authoritative. The packet route may display
the first row locally when `packetId` is absent, but it writes the URL only
after explicit operator selection. A selected-id key alone does not clear
committed Suspense content while the replacement query suspends, as the
stale-detail behavior test demonstrates. The run route therefore retains one
transition-only pending id to render loading until the URL commit, replacing
the previous boolean-plus-ref mirror without becoming a second durable
selection source.

### Relay owns cumulative activity

The detail query exposes a refetchable activity connection fragment.
`usePaginationFragment` owns accumulated edges, duplicate suppression,
continuation state, and retry. The list remains page-replacing and keeps its
existing cursor history because that is distinct product behavior.

### GraphQL documents match rendered data

The run index returns only list fields and performs one run-page read plus one
batched packet read. Selected detail remains the source for packet-version,
checks, evidence, results, and activity. Queries request only fields rendered
by those components.

### Tests stay at observable boundaries

Derive fixtures from generated operation types, remove duplicated scenarios and
the BrowserRouter/global `Request` patch, and test worker dispatch posture
through worker behavior rather than a public internal helper.

## Risks / Trade-offs

- **Local databases created from the invalid migration history no longer
  upgrade in place** → The project already requires reset for unreleased
  incompatible history; document this in the change and retain fresh-install
  migration coverage.
- **Narrower public run summaries remove unused fields** → The product is
  unreleased and has no named external consumer; selected detail retains the
  richer contract.
- **Relay pagination changes error handling shape** → Preserve already loaded
  activity and expose a safe retry through behavior tests before removing the
  manual request model.
- **Smaller architecture checks cover fewer hypothetical source forms** →
  TypeScript, Biome, Relay compilation, React Router build, and dependency
  verification cover those language and tool mechanics.
