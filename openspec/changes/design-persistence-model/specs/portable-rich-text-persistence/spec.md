## ADDED Requirements

### Requirement: Editor-Independent Rich Text Model
Office Graph SHALL persist rich text bodies in an Office Graph rich text schema
rather than in a frontend-editor-specific payload.

#### Scenario: Rich text body is saved
- **WHEN** a description, discussion comment, conversation message,
  requirement body, decision body, document section, plan section, or native
  comment body is saved
- **THEN** the canonical durable content MUST be stored as normalized Office
  Graph rich text records, with Lexical or any future editor represented only
  through adapters and derived renders

#### Scenario: Editor payload is needed
- **WHEN** Lexical JSON, HTML, Markdown, or another editor-specific payload is
  generated for editing, preview, export, or agent context
- **THEN** it MUST be derived from the Office Graph rich text model and tied to
  a source revision and renderer or adapter version

### Requirement: Normalized Rich Text Structure
Office Graph SHALL normalize rich text into document, revision, block, inline,
mark, reference, and render structures.

#### Scenario: Rich text structure is stored
- **WHEN** rich text content is persisted
- **THEN** documents, document revisions, stable blocks, block versions, stable
  inline nodes, inline versions, mark types, versioned mark applications,
  typed references, and derived renders MUST be representable without storing
  the canonical content as a single JSON document

#### Scenario: First portable schema is implemented
- **WHEN** the first rich text schema is built
- **THEN** it MUST support paragraphs, headings, ordered and unordered lists,
  list items, quotes, code blocks, text runs, hard breaks, basic inline marks,
  and typed references for principals, graph items, external references, URLs,
  and artifacts

### Requirement: Copy-On-Write Rich Text Revisions
Office Graph SHALL store rich text revision history as semantic commits with
changed content versions rather than full document snapshots.

#### Scenario: Single word is bolded
- **WHEN** a user applies a mark to one word inside a rich text document
- **THEN** Office Graph MUST create a new document revision and mark-version
  change for the affected inline node without recreating unchanged blocks,
  inline nodes, references, or render-independent document structure

#### Scenario: Rich text revision is reconstructed
- **WHEN** Office Graph reconstructs a rich text document revision
- **THEN** it MUST use copy-on-write version rows, revision validity ranges,
  placement-version state, and derived render caches rather than treating full
  materialized snapshots as canonical storage

#### Scenario: Text range receives a mark
- **WHEN** a mark applies to only part of an inline text run
- **THEN** the editor adapter MUST split the text into stable inline nodes as
  needed before applying versioned mark rows to the affected inline nodes

### Requirement: Normalized Mark Types
Office Graph SHALL represent rich text styling and semantic annotations through
mark type definitions and versioned mark applications.

#### Scenario: New mark type is introduced
- **WHEN** a supported mark such as bold, italic, underline, code, text color,
  highlight, comment highlight, or a future semantic annotation is added
- **THEN** it MUST be represented by a mark type with key, value kind,
  compatibility or exclusivity rules, introduction version, and deprecation
  state rather than by adding one-off columns to inline text rows

#### Scenario: MVP mark set is selected
- **WHEN** the MVP mark set is selected
- **THEN** bold, italic, underline, strikethrough, inline code, highlight, and
  link presentation MUST be representable without adding mark-specific columns
  to inline text rows

### Requirement: Typed Rich Text References
Office Graph SHALL extract mentions, graph-item references, artifact links,
external links, and future attachment references into typed relational rows.

#### Scenario: Rich text references Office Graph data
- **WHEN** rich text contains a principal mention, graph item reference,
  review-comment reference, artifact reference, external reference, URL, or
  attachment
- **THEN** the reference MUST be stored as typed relational data linked to the
  applicable target and stable inline anchor so authorization, notifications,
  graph traversal, search, and agent context do not parse editor payloads

### Requirement: Non-Invasive Anchors And Quotes
Office Graph SHALL model rich text anchors, references, and quotes as sidecar
records unless a user explicitly inserts a visible source anchor or bookmark.

#### Scenario: Quote is created from another document
- **WHEN** a user quotes or references selected content from a source rich text
  document
- **THEN** Office Graph MUST create quote/reference metadata and MUST NOT alter
  the source document solely to support that quote or reference

#### Scenario: Named source anchor is inserted
- **WHEN** a user explicitly creates a durable named anchor or bookmark inside
  the source document
- **THEN** that anchor insertion is a normal source document edit with its own
  revision and authorization checks

### Requirement: Pinned Quotes Preserve Source State
Office Graph SHALL preserve pinned quotes against the source revision and
selected source span that produced them.

#### Scenario: Pinned quote is saved
- **WHEN** selected source content is inserted as a pinned quote
- **THEN** the quote MUST record source document, source revision, selected
  block or inline range, copied normalized snapshot fragment, snapshot digest,
  provenance, and source authorization or classification context

#### Scenario: Source content later changes
- **WHEN** the quoted source content is later edited, deleted, or reordered
- **THEN** the pinned quote MUST continue rendering the saved snapshot and MAY
  expose source-changed, source-deleted, or source-reordered status without
  silently mutating the quote text

### Requirement: Live References Resolve With Status
Office Graph SHALL distinguish live references from pinned quotes.

#### Scenario: Live reference is rendered
- **WHEN** a live reference or live excerpt is rendered
- **THEN** Office Graph MUST resolve it against the latest authorized source
  state and return a resolution status such as resolved, stale, deleted,
  ambiguous, unauthorized, or source-reordered

#### Scenario: Live reference cannot be safely resolved
- **WHEN** the referenced source span cannot be mapped unambiguously to the
  latest source revision
- **THEN** Office Graph MUST avoid fabricating updated quote text and MUST
  render an explicit unresolved or stale state for users and agents

### Requirement: Selection Intent Is Preserved
Office Graph SHALL model source selections according to user intent rather
than treating every selection as a mutable text boundary range.

#### Scenario: Selection crosses inline formatting
- **WHEN** a selected quote spans multiple inline runs or marks, such as text
  that begins inside bold text and ends inside italic text
- **THEN** the anchor/range model MUST represent start and end inline anchors
  with offsets and preserve the copied marked fragment for pinned quotes

#### Scenario: Several list items are selected
- **WHEN** a user selects multiple list items to quote or reference
- **THEN** Office Graph MUST represent the selection as a block selection set
  by stable block identities unless the user explicitly chooses a boundary
  range

#### Scenario: Source list items are reordered
- **WHEN** source list items referenced by a pinned quote are later reordered
- **THEN** the pinned quote MUST preserve the original selected order and MAY
  mark the source as reordered; live excerpts MUST define whether they render
  in original selection order or current source order

### Requirement: Unsupported Rich Text Features
Office Graph SHALL handle unsupported editor features explicitly instead of
silently storing them in canonical editor payloads.

#### Scenario: Unsupported native editor feature is submitted
- **WHEN** native authoring submits content that the portable schema cannot
  represent safely
- **THEN** Office Graph MUST reject the feature, flatten it when it is
  style-only, or store it as an artifact/raw adapter payload until an accepted
  design promotes it into the portable schema

### Requirement: Agent Markdown Is Derived
Office Graph SHALL serialize rich text to agent Markdown as a derived render
with stable Office Graph references.

#### Scenario: Agent context includes rich text
- **WHEN** rich text is included in an embedded-agent conversation, work
  packet, run context, review, verification step, or export
- **THEN** the context assembler MUST derive Markdown or another approved
  text representation from the authorized rich text revision and reference
  tables, applying redaction or placeholders where policy requires it
