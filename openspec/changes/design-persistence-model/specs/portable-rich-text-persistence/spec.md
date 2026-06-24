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
  `rich_text_documents`, current `rich_text_blocks`, versioned
  `rich_text_block_versions`, stable text-run or inline span identities,
  basic inline mark types and mark applications, typed references, pinned
  quote snapshots when present, and whole-document semantic
  `rich_text_document_revisions` rather than Lexical JSON or another
  frontend-editor payload as canonical storage

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
  task lists, block versions, mark-type definitions, mark applications, and
  basic marks for bold, italic, inline code, links, principal mentions, graph
  item references, external references, URLs, and artifact references

#### Scenario: Rich text references Office Graph data
- **WHEN** rich text contains a principal mention, graph item reference,
  artifact reference, external reference, or URL
- **THEN** the reference MUST be stored as typed relational data or a typed
  reference row so authorization, notifications, graph traversal, search, and
  agent context do not parse editor payloads

### Requirement: Pinned Exact-Span Quote Snapshots For V1
Office Graph SHALL support pinned exact-span rich text quote snapshots in the
first rich text cut without live-updating quoted text.

#### Scenario: Exact span is quoted
- **WHEN** a user quotes an exact phrase, sentence, list item, block, or
  multi-block selection from a rich text document
- **THEN** Office Graph MUST store a pinned quote snapshot with source
  document, source revision, source authorization/classification context,
  copied normalized snapshot fragment, ordered selection segments, segment
  hashes, and operation correlation

#### Scenario: Non-consecutive list items are quoted
- **WHEN** a user quotes multiple non-consecutive items from a list
- **THEN** the quote MUST store those items as ordered selection segments in
  user-selected order rather than as one loose start/end range

#### Scenario: Quote is rendered
- **WHEN** a pinned quote is displayed in a projection, conversation, evidence
  chain, review surface, or API response
- **THEN** the primary displayed text MUST be the pinned snapshot, with a
  freshness indicator when the source has changed and an authorized path to
  inspect current source state when available

#### Scenario: Source permissions change after quote creation
- **WHEN** a viewer can access the quote container but cannot currently access
  the quoted source range
- **THEN** Office Graph MUST hide or redact the quote content and show a
  restricted-source state unless the quote has been explicitly promoted into a
  standalone evidence or artifact record with its own authorization

### Requirement: Quote Freshness States For V1
Office Graph SHALL distinguish source freshness states for pinned quote
snapshots.

#### Scenario: Source changes after quote creation
- **WHEN** a quote source has a newer internal revision than the source
  revision captured by the quote
- **THEN** Office Graph MUST distinguish `source_changed_elsewhere` from
  `quoted_selection_changed` when segment hashes and stable source identities
  make that comparison possible

#### Scenario: Quote source cannot be resolved
- **WHEN** the quoted source range is deleted, cannot be mapped cleanly, or is
  no longer visible to the actor
- **THEN** Office Graph MUST report a freshness state such as
  `selection_unresolvable`, `source_deleted`, or `source_access_restricted`
  rather than silently rendering the quote as current

#### Scenario: Quote is still current
- **WHEN** the source document has not changed or the selected segment hashes
  still match the latest authorized internal revision
- **THEN** Office Graph MAY report `current` or `source_changed_elsewhere`
  according to whether only unrelated source content changed

### Requirement: Imported Rich Text Quote Sources Normalize Internally
Office Graph SHALL quote imported provider content through internal normalized
Office Graph rich text records rather than provider payloads directly.

#### Scenario: Imported content is quoted
- **WHEN** a user quotes imported provider content such as an external
  document, provider comment, or synced artifact body
- **THEN** Office Graph MUST create or reuse an internal normalized artifact or
  rich text document revision and point the quote selection segments at that
  internal representation, while retaining external reference and raw archive
  provenance

#### Scenario: Provider content changes
- **WHEN** provider sync detects that a quoted external source changed
- **THEN** Office Graph MUST automatically create a new internal normalized
  revision when the source can still be read and surface provider freshness
  such as `external_source_updated` or `external_source_unavailable` without
  changing the pinned quote text

### Requirement: Rich Text V1 Extension Contract
Office Graph SHALL keep the first rich text schema small while preserving an
upgrade path for later editor, quote, collaboration, and reconstruction
features.

#### Scenario: V1 rich text records are created
- **WHEN** the first backend cut creates rich text documents, blocks, marks,
  references, quote snapshots, revisions, or derived plain text
- **THEN** those records MUST use stable document, block, text-run or inline
  span, reference, quote, revision, and operation-correlation identities that
  future inline-version, live-anchor, render-cache, collaboration, and
  editor-adapter tables can reference without replacing the v1 document or
  block model

#### Scenario: Deferred rich text feature is added later
- **WHEN** a future accepted rich text implementation adds per-inline
  reconstruction, automatic source-range re-anchoring, live quote updating,
  collaboration state, render caches, rich diff views, or persisted
  editor-adapter payloads
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
  ranges, live quote updating, automatic source-range re-anchoring,
  collaboration/session state, HTML render caches, rich diff views, or Lexical
  adapter persistence
- **THEN** that feature MUST wait for a future rich text implementation change
  rather than blocking the first backend walking skeleton

### Requirement: Derived Plain Text For V1
Office Graph SHALL derive plain text from authorized rich text where search,
display fallback, or agent context requires it.

#### Scenario: Agent or search context needs text
- **WHEN** search indexing, graph summaries, verification context, or agent
  context needs text from a rich text body
- **THEN** Office Graph MAY store `rich_text_derived_plain_texts` or compute
  derived plain text tied to the current document revision, applying
  authorization and redaction policy before exposing it

### Requirement: Unsupported Rich Text Features
Office Graph SHALL handle unsupported editor features explicitly instead of
silently storing them in canonical editor payloads.

#### Scenario: Unsupported native editor feature is submitted
- **WHEN** native authoring submits content that the v1 portable schema cannot
  represent safely
- **THEN** Office Graph MUST reject the feature, flatten it when it is
  style-only, or store it as an artifact/raw adapter payload until an accepted
  future design promotes it into the portable schema
