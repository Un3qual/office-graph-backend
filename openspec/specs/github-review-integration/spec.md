# github-review-integration Specification

## Purpose

Define authenticated GitHub App intake, provider-neutral reconciliation,
narrow outbound review actions, and classified failure handling.

## Requirements

### Requirement: GitHub Installations Are Explicitly Bound

Office Graph SHALL bind a GitHub App installation to one organization, optional
governing workspace, service principal, permission snapshot, and credential
references through a narrow authorized command.

#### Scenario: Authorized owner binds installation

- **WHEN** an authorized local owner submits a valid installation identity,
  scope, service principal, permissions, and secret references
- **THEN** Office Graph MUST create or idempotently return the installation
  binding without returning secret values

#### Scenario: Workspace-scoped owner requests organization binding

- **WHEN** an owner whose installation-binding capability is assigned only to
  the current workspace requests a binding with no governing workspace
- **THEN** Office Graph MUST reject the request without creating an
  organization-scoped installation, principal role, or credential binding

#### Scenario: Organization-scoped owner requests organization binding

- **WHEN** an owner with an organization-scoped installation-binding grant
  requests a binding with no governing workspace
- **THEN** Office Graph MUST create or idempotently return the
  organization-scoped binding without returning secret values

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

#### Scenario: Manual intake has reused a provider source key

- **WHEN** a manual external source and a GitHub provider source use the same key
- **THEN** Office Graph MUST keep their source-kind identities independent so
  manual intake cannot block authenticated webhook archival or job creation

#### Scenario: Webhook secret store is temporarily unavailable

- **WHEN** signature verification cannot resolve the bound webhook secret due to
  a transient secret-store outage
- **THEN** Office Graph MUST return a retryable service response without
  misclassifying the delivery as an invalid signature or creating receipt effects

#### Scenario: Receipt authentication records are temporarily unavailable

- **WHEN** webhook receipt cannot read its installation or credential binding
  because integration storage is temporarily unavailable
- **THEN** Office Graph MUST return a retryable service response without
  misclassifying the installation or signature or creating receipt effects

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
  provider-neutral state, signal content, or external-reference URLs

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

#### Scenario: Sparse provider reference omits or blanks its URL

- **WHEN** a later provider snapshot omits the optional URL or supplies a blank
  value for an existing external reference
- **THEN** Office Graph MUST preserve the last known URL until a non-empty
  replacement is available

#### Scenario: Review signal becomes product work

- **WHEN** a reconciled review comment or failing check matches the proving
  workflow
- **THEN** Office Graph MUST create the authorized signal, external references,
  and canonical typed relationships through owning domain commands

#### Scenario: Provider review work becomes non-actionable

- **WHEN** a newer reconciliation marks a review comment pending, minimized, or
  deleted, marks its containing review thread resolved or outdated, or marks a
  previously failing check non-failing
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

#### Scenario: Reply target is no longer published

- **WHEN** an actor requests a reply to a pending, minimized, or deleted review
  comment
- **THEN** Office Graph MUST reject the command before action enqueue,
  credential resolution, or provider access

#### Scenario: Review reply contains intentional Markdown whitespace

- **WHEN** an actor submits a nonblank review reply with leading indentation or
  surrounding newlines
- **THEN** Office Graph MUST preserve the exact body through durable action
  storage and provider delivery

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

#### Scenario: Integration record lookup is temporarily unavailable

- **WHEN** a valid webhook, reconciliation, outbound command, outbound job, or
  health read cannot read its installation, archived delivery, permission
  snapshot, outbound action, target, credential metadata, or dependent health
  record because storage is temporarily unavailable
- **THEN** Office Graph MUST preserve a retryable storage-unavailable result,
  MUST NOT misclassify the record as revoked, invalid, cross-scope, forbidden,
  or terminal, and durable work MUST retain that classification within its fixed
  attempt budget
- **AND** public JSON command and health responses MUST use HTTP 503 while JSON
  and GraphQL expose only the safe `integration_storage_unavailable` code and
  no internal storage detail

#### Scenario: GitHub rate limit is returned

- **WHEN** an adapter call returns a valid rate-limit reset
- **THEN** the job MUST retry no earlier than the bounded reset policy and health
  MUST expose a safe rate-limit state

#### Scenario: Installation is revoked

- **WHEN** GitHub reports that an installation is revoked
- **THEN** Office Graph MUST atomically persist the installation's revoked
  lifecycle only when its terminal revoked outcome wins any concurrent outcome
  race, new provider work MUST fail closed, and historical provenance MUST remain

#### Scenario: Installation credential is invalid

- **WHEN** a bound installation credential is invalid but GitHub has not
  reported the installation as revoked
- **THEN** Office Graph MUST retain the installation lifecycle, record the
  terminal invalid-credential outcome, and direct operators to rotate credentials

#### Scenario: Stored outbound secret is missing

- **WHEN** the selected outbound credential resolves to a missing or invalid
  secret reference
- **THEN** the action MUST fail terminally as an invalid credential before
  provider access and health MUST expose credential-rotation remediation

#### Scenario: GitHub denies an outbound action

- **WHEN** GitHub rejects an outbound action because the installation no longer
  has permission
- **THEN** Office Graph MUST retain an authorization failure classification and
  MUST stop retrying the action, and health MUST direct operators to reauthorize
  the installation

#### Scenario: Webhook reconciliation terminates

- **WHEN** an inbound reconciliation job reaches a classified non-retryable
  failure
- **THEN** its durable job history MUST retain the same safe failure code even
  when the receipt event does not carry that terminal state

#### Scenario: Outbound action terminates

- **WHEN** an outbound job reaches a classified terminal action outcome
- **THEN** its durable job history MUST retain the same safe failure code so
  operators can diagnose the terminal reason without reading raw job errors

#### Scenario: Outbound action storage is unavailable at retry exhaustion

- **WHEN** the final outbound attempt cannot read its action record because
  integration storage is temporarily unavailable
- **THEN** the worker MUST persist a terminalization phase, retry the action
  state transition after storage recovers, and MUST NOT cancel while the action
  remains pending

#### Scenario: Webhook storage is unavailable before operation start at retry exhaustion

- **WHEN** the final inbound attempt cannot load the installation or receipt
  operation because integration storage is temporarily unavailable
- **THEN** the worker MUST persist a terminalization phase, durably record the
  terminal provider-delivery outcome and failed receipt after storage recovers,
  expose the classified failure through health, and MUST NOT cancel first
