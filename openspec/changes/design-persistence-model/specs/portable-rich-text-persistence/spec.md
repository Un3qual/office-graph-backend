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

### Requirement: Copy-On-Write Rich Text Revisions
Office Graph SHALL store rich text revision history as semantic commits with
changed content versions rather than full document snapshots.

#### Scenario: Single word is bolded
- **WHEN** a user applies a mark to one word inside a rich text document
- **THEN** Office Graph MUST create a new document revision and mark-version
  change for the affected inline node without recreating unchanged blocks,
  inline nodes, references, or render-independent document structure

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

### Requirement: Agent Markdown Is Derived
Office Graph SHALL serialize rich text to agent Markdown as a derived render
with stable Office Graph references.

#### Scenario: Agent context includes rich text
- **WHEN** rich text is included in an embedded-agent conversation, work
  packet, run context, review, verification step, or export
- **THEN** the context assembler MUST derive Markdown or another approved
  text representation from the authorized rich text revision and reference
  tables, applying redaction or placeholders where policy requires it
