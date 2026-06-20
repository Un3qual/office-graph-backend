## 1. Review And Acceptance

- [x] 1.1 Confirm this change is design-only and does not implement ingestion,
  webhooks, Oban jobs, provider adapters, API endpoints, UI, or migrations.
- [x] 1.2 Confirm manual pasted intake is the first walking-skeleton adapter.
- [x] 1.3 Confirm adapters output typed provider-neutral envelopes and do not
  mutate graph truth tables directly.

## 2. Capability Spec Review

- [x] 2.1 Review `manual-intake-adapter`.
- [x] 2.2 Review `external-event-normalization`.
- [x] 2.3 Review `idempotency-and-replay`.
- [x] 2.4 Review `provider-adapter-contract`.
- [x] 2.5 Review `sync-state-machine`.

## 3. Follow-On Planning Work

- [x] 3.1 Feed adapter behaviours into `design-code-organization-and-boundaries`.
- [ ] 3.2 Feed raw archive and replay storage needs into first backend walking
  skeleton planning.
- [x] 3.3 Feed proposed mutation routing into `design-proposed-graph-changes`.
- [ ] 3.4 Feed webhook/source principal requirements into future integration
  implementation plans.

## 4. Validation

- [x] 4.1 Run `openspec validate design-ingestion-and-integrations --strict`.
- [x] 4.2 Run `openspec validate --changes --strict`.
