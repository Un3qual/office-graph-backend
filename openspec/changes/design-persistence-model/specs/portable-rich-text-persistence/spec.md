## ADDED Requirements

### Requirement: Rich Text V1 Portable Storage
Office Graph SHALL persist first-cut rich text bodies in a normalized,
editor-independent model without requiring full per-inline copy-on-write
reconstruction.

#### Scenario: Rich text body is saved in v1
- **WHEN** a task description, review finding body, evidence note,
  conversation message, requirement body, decision body, or plan-section body
  is saved in the first backend cut
- **THEN** the canonical durable content MUST use normalized
  `rich_text_documents`, current `rich_text_blocks`, basic inline marks, typed
  references, and whole-document semantic revision records rather than Lexical
  JSON or another frontend-editor payload as canonical storage

#### Scenario: Editor payload is needed
- **WHEN** Lexical JSON, HTML, Markdown, or another editor-specific payload is
  generated for editing, preview, export, or agent context
- **THEN** it MUST be derived from the Office Graph rich text model and tied to
  a source revision or renderer version rather than stored as canonical product
  state

### Requirement: Rich Text V1 Structure
Office Graph SHALL keep the first rich text schema narrow enough to support
the walking skeleton.

#### Scenario: First portable schema is selected
- **WHEN** the first rich text schema is built
- **THEN** it MUST support documents, current blocks, text runs, paragraphs or
  equivalent plain blocks, ordered and unordered list blocks where needed for
  task lists, and basic marks for bold, italic, inline code, links, principal
  mentions, graph item references, external references, URLs, and artifact
  references

#### Scenario: Rich text references Office Graph data
- **WHEN** rich text contains a principal mention, graph item reference,
  artifact reference, external reference, or URL
- **THEN** the reference MUST be stored as typed relational data or a typed
  reference row so authorization, notifications, graph traversal, search, and
  agent context do not parse editor payloads

### Requirement: Rich Text V1 Extension Contract
Office Graph SHALL keep the first rich text schema small while preserving an
upgrade path for later editor, quote, collaboration, and reconstruction
features.

#### Scenario: V1 rich text records are created
- **WHEN** the first backend cut creates rich text documents, blocks, marks,
  references, revisions, or derived plain text
- **THEN** those records MUST use stable document, block, reference, revision,
  and operation-correlation identities that future inline-version,
  range-anchor, quote-snapshot, render-cache, collaboration, and editor-adapter
  tables can reference without replacing the v1 document or block model

#### Scenario: Deferred rich text feature is added later
- **WHEN** a future accepted rich text implementation adds per-inline
  reconstruction, source-range anchoring, quote snapshots, live quote
  resolution, collaboration state, render caches, or persisted editor-adapter
  payloads
- **THEN** it MUST extend the v1 normalized rich text model through additive
  tables, typed backfills, or renderer records tied to source revisions rather
  than making Lexical JSON, HTML, Markdown, or another editor payload the new
  canonical state

#### Scenario: Unsupported imported content is promoted
- **WHEN** imported artifact or raw adapter payload content is later promoted
  into first-class rich text
- **THEN** the promotion MUST preserve provenance and create normalized
  document, block, mark, reference, and revision records instead of exposing
  the raw payload as the normal query, authorization, or agent-context surface

### Requirement: Whole-Document Semantic Revisions For V1
Office Graph SHALL use whole-document semantic revision records for the first
rich text cut.

#### Scenario: Description changes in v1
- **WHEN** a user changes one word, one mark, or one reference in a rich text
  body during the first backend cut
- **THEN** Office Graph MUST record a semantic document revision with actor,
  operation correlation, parent revision, reason when available, and current
  document state sufficient for audit/revision linkage

#### Scenario: Fine-grained reconstruction is requested
- **WHEN** a feature needs per-inline copy-on-write reconstruction, validity
  ranges, quote snapshots, live quote resolution, selection-intent
  preservation, collaboration/session state, HTML render caches, Lexical
  adapter persistence, or source-range anchoring
- **THEN** that feature MUST wait for a future rich text implementation change
  rather than blocking the first backend walking skeleton

### Requirement: Derived Plain Text For V1
Office Graph SHALL derive plain text from authorized rich text where search,
display fallback, or agent context requires it.

#### Scenario: Agent or search context needs text
- **WHEN** search indexing, graph summaries, verification context, or agent
  context needs text from a rich text body
- **THEN** Office Graph MAY store or compute derived plain text tied to the
  current document revision, applying authorization and redaction policy before
  exposing it

### Requirement: Unsupported Rich Text Features
Office Graph SHALL handle unsupported editor features explicitly instead of
silently storing them in canonical editor payloads.

#### Scenario: Unsupported native editor feature is submitted
- **WHEN** native authoring submits content that the v1 portable schema cannot
  represent safely
- **THEN** Office Graph MUST reject the feature, flatten it when it is
  style-only, or store it as an artifact/raw adapter payload until an accepted
  future design promotes it into the portable schema
