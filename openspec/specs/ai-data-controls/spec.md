# ai-data-controls Specification

## Purpose

Define organization AI provider policy, sensitive context filtering, model provenance, detection, and provider terms controls.

## Requirements

### Requirement: Organization AI Provider Policy

Office Graph SHALL allow organization policy to govern which AI providers,
models, and model classes may receive particular categories of data.

#### Scenario: Model call is prepared

- **WHEN** Office Graph prepares a model call for an agent, embedded
  conversation, review, summarization, or change proposal
- **THEN** the system must evaluate organization AI provider policy against
  resource sensitivity labels, data categories, tool context, requested model,
  provider terms, and retention settings

#### Scenario: Provider is disallowed

- **WHEN** organization policy disallows a provider or model for the selected
  context
- **THEN** the runtime must block the model call, select an allowed
  alternative, redact or summarize context according to policy, or require an
  authorized approval

### Requirement: Sensitive Context Filtering

Office Graph SHALL filter, redact, summarize, or withhold sensitive context
before it reaches agents or model providers when policy requires it.

#### Scenario: Context package contains sensitive data

- **WHEN** a context package includes source code, credentials, customer data,
  finance-sensitive data, legal-sensitive data, security-sensitive data,
  secret data, or restricted artifacts
- **THEN** the context assembly pipeline must apply authorization and AI data
  controls before the context is delivered to a model or agent

#### Scenario: Redacted context is used

- **WHEN** redacted or summarized context is provided instead of raw data
- **THEN** the system must preserve enough provenance to explain that context
  was restricted and why, without exposing restricted payloads

### Requirement: Prompt And Model Provenance Controls

Office Graph SHALL record model and prompt provenance according to
organization retention and sensitivity policy.

#### Scenario: Agent run uses a model

- **WHEN** an agent run, embedded conversation, automatic review, or model
  pipeline uses a model
- **THEN** the system must record model provider, model identifier or policy
  reference, prompt or prompt-policy reference, input/output storage policy,
  related run, related graph item, and data-control decision according to
  organization policy

#### Scenario: Prompt storage is restricted

- **WHEN** organization or sensitivity policy restricts prompt or model
  output storage
- **THEN** the system must preserve policy-compliant metadata and provenance
  without storing disallowed raw prompt or output content

### Requirement: Secret And Sensitive Data Detection

Office Graph SHALL support secret and sensitive-data detection before external
model calls and high-risk tool actions.

#### Scenario: Context is assembled for external model use

- **WHEN** source code, documents, external payloads, comments, credentials,
  or user-provided text are assembled for external model use
- **THEN** the system must be able to run detection for secrets and sensitive
  data and then block, redact, summarize, or approval-gate the action

#### Scenario: Detection finds a secret

- **WHEN** detection finds a credential, token, secret, or similarly sensitive
  value
- **THEN** the runtime must prevent unapproved exposure and record the
  governance decision according to audit and data-control policy

### Requirement: Provider Terms Metadata

Office Graph SHALL track provider terms relevant to enterprise AI governance.

#### Scenario: Provider is configured

- **WHEN** an AI provider or model provider account is configured
- **THEN** Office Graph must be able to record no-training status, retention
  terms, regional processing constraints when available, data-use policy,
  allowed sensitivity labels, and approval requirements

#### Scenario: Provider terms change

- **WHEN** provider terms or organization policy changes
- **THEN** future model calls must use the updated policy and historical
  governance records must remain interpretable
