## ADDED Requirements

### Requirement: GitHub Installations Are Explicitly Bound

Office Graph SHALL bind a GitHub App installation to one organization, optional
governing workspace, service principal, permission snapshot, and credential
references through a narrow authorized command.

#### Scenario: Authorized owner binds installation

- **WHEN** an authorized local owner submits a valid installation identity,
  scope, service principal, permissions, and secret references
- **THEN** Office Graph MUST create or idempotently return the installation
  binding without returning secret values

#### Scenario: Unauthenticated setup is attempted

- **WHEN** a request without an authorized human session attempts to bind an
  installation
- **THEN** Office Graph MUST reject it without revealing another tenant's
  installation state

### Requirement: GitHub Webhooks Are Verified Before Product Intake

Office Graph SHALL verify webhook signature and installation binding before
archiving a payload or creating product work.

#### Scenario: Valid supported delivery arrives

- **WHEN** a supported event has a valid signature and active installation
  binding
- **THEN** Office Graph MUST create a system operation, archive the payload,
  enqueue one durable delivery, and return promptly

#### Scenario: Signature or installation is invalid

- **WHEN** signature verification fails or the installation is unknown, revoked,
  or outside scope
- **THEN** Office Graph MUST reject the delivery before product payload archival
  or job creation

#### Scenario: Delivery is replayed

- **WHEN** GitHub repeats a delivery ID with the same authenticated installation
- **THEN** Office Graph MUST return the prior receipt outcome without duplicate
  resource, signal, event, or job effects

#### Scenario: Webhook secret store is temporarily unavailable

- **WHEN** signature verification cannot resolve the bound webhook secret due to
  a transient secret-store outage
- **THEN** Office Graph MUST return a retryable service response without
  misclassifying the delivery as an invalid signature or creating receipt effects

### Requirement: GitHub State Is Reconciled Into Provider-Neutral Resources

Office Graph SHALL reconcile supported repository, pull request, review,
review-comment, and check activity into provider-neutral resources and GitHub
extension records.

#### Scenario: Partial webhook is processed

- **WHEN** a webhook does not contain authoritative current provider state
- **THEN** the durable handler MUST schedule or perform an installation-scoped
  adapter read before updating provider-neutral truth

#### Scenario: Older provider version arrives

- **WHEN** a delivery or reconciliation result is older than the stored provider
  version
- **THEN** Office Graph MUST skip or reconcile it and MUST NOT overwrite newer
  state

#### Scenario: The same provider object is visible in multiple workspaces

- **WHEN** two installations in one organization reconcile the same GitHub object
  under different governing workspaces
- **THEN** Office Graph MUST retain independent workspace-scoped provider-neutral
  resources, extension identities, and external references

#### Scenario: A non-pull-request delivery is reconciled

- **WHEN** a review-comment or check delivery requests an authoritative read
- **THEN** the returned snapshot MUST contain the requested object, while a review
  submission SHALL reconcile through its containing pull request identity

#### Scenario: Requested-object collection is malformed

- **WHEN** an adapter returns a missing or malformed review-comment or check-run
  collection for a requested-object delivery
- **THEN** reconciliation MUST record a classified invalid-provider-response
  outcome without crashing or writing partial provider-neutral state

#### Scenario: Concurrent reconciliation writers overlap

- **WHEN** concurrent handlers write failure and success for one reconciliation
  operation or materialize the same scoped external-reference identity
- **THEN** Office Graph MUST serialize or atomically converge those writes to one
  outcome and one reference, and a successful outcome MUST NOT be downgraded

#### Scenario: Provider ownership or signal scope does not match

- **WHEN** a provider source attempts to update another source's resource, or a
  reference does not match the reconciliation operation's workspace
- **THEN** Office Graph MUST reject the write before changing provider-neutral
  truth or creating graph state

#### Scenario: Sparse provider reference omits its URL

- **WHEN** a later provider snapshot omits the optional URL for an existing
  external reference
- **THEN** Office Graph MUST preserve the last known URL until a non-empty
  replacement is available

#### Scenario: Review signal becomes product work

- **WHEN** a reconciled review comment or failing check matches the proving
  workflow
- **THEN** Office Graph MUST create the authorized signal, external references,
  and canonical typed relationships through owning domain commands

#### Scenario: Provider review work becomes non-actionable

- **WHEN** a newer reconciliation marks a review comment pending, minimized, or
  deleted, or marks a previously failing check non-failing
- **THEN** Office Graph MUST close the existing mapped signal without deleting
  its provenance, MUST NOT create an open signal for first-seen non-actionable
  state, and MUST reopen the same signal identity if the provider item later
  becomes actionable again

#### Scenario: Actionable provider review work changes

- **WHEN** a newer reconciliation changes the title or body of an actionable
  review comment or failing check
- **THEN** Office Graph MUST refresh the existing canonical signal and graph-item
  content without replacing its identity or losing the prior content provenance

#### Scenario: GitHub returns provider-only check states

- **WHEN** GitHub returns a check in requested, waiting, or pending state, or a
  completed check with a stale conclusion
- **THEN** reconciliation MUST normalize the waiting-family states to the
  provider-neutral queued state and MUST preserve stale as a non-failing
  completed conclusion

### Requirement: GitHub Outbound Actions Are Narrow And Authorized

Office Graph SHALL expose only review-reply and status/check-update commands for
the first GitHub integration.

#### Scenario: Authorized reply is requested

- **WHEN** an actor with required capability, installation permission,
  credential scope, operation, and idempotency key requests a review reply
- **THEN** Office Graph MUST enqueue one provider action and record its provider
  response identity and classified outcome, and the adapter request MUST carry
  the selected external installation identity

#### Scenario: Review-reply success is ambiguous

- **WHEN** GitHub may have created a reply before Office Graph persisted the
  successful provider response
- **THEN** the adapter request MUST carry the durable action identity and the
  worker MUST reconcile that identity before attempting another reply create

#### Scenario: Selected installation does not own target provenance

- **WHEN** an outbound action selects an installation that has not reconciled the
  target pull request
- **THEN** Office Graph MUST reject the action before credential or provider access

#### Scenario: Outbound target changes after enqueue

- **WHEN** a reconciled review comment or check run has a different provider
  version when its queued or retried outbound action is ready to call GitHub
- **THEN** the worker MUST reject the stale action before provider access and
  persist a classified stale-provider-version outcome

#### Scenario: Check progress is updated

- **WHEN** an authorized caller updates a check to queued or in-progress
- **THEN** the command MUST omit a conclusion, while completed checks MUST provide
  a provider-writable supported conclusion and MUST reject provider-only states
  such as startup_failure

#### Scenario: Repository write is requested

- **WHEN** a caller requests a commit, branch write, merge, or other unsupported
  repository mutation
- **THEN** the integration MUST reject it before credential resolution or
  provider access

### Requirement: GitHub Failures Are Classified

Office Graph SHALL classify provider failures as retryable, terminal,
authorization, configuration, rate-limit, or stale-version outcomes.

#### Scenario: GitHub rate limit is returned

- **WHEN** an adapter call returns a valid rate-limit reset
- **THEN** the job MUST retry no earlier than the bounded reset policy and health
  MUST expose a safe rate-limit state

#### Scenario: Installation is revoked

- **WHEN** GitHub reports a revoked installation or invalid credential
- **THEN** new provider work MUST fail closed, active retries MUST become
  configuration or terminal state, and historical provenance MUST remain

#### Scenario: Stored outbound secret is missing

- **WHEN** the selected outbound credential resolves to a missing or invalid
  secret reference
- **THEN** the action MUST fail terminally as an invalid credential before
  provider access and health MUST expose credential-rotation remediation

#### Scenario: GitHub denies an outbound action

- **WHEN** GitHub rejects an outbound action because the installation no longer
  has permission
- **THEN** Office Graph MUST retain an authorization failure classification and
  MUST stop retrying the action

#### Scenario: Webhook reconciliation terminates

- **WHEN** an inbound reconciliation job reaches a classified non-retryable
  failure
- **THEN** its durable job history MUST retain the same safe failure code even
  when the receipt event does not carry that terminal state

#### Scenario: Outbound action terminates

- **WHEN** an outbound job reaches a classified terminal action outcome
- **THEN** its durable job history MUST retain the same safe failure code so
  operators can diagnose the terminal reason without reading raw job errors
