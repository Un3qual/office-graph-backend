## MODIFIED Requirements

### Requirement: Console Presents Workflow Inbox And Item Detail
The operator console SHALL let an operator inspect the actionable workflow inbox
and selected item detail through the product GraphQL data path.

#### Scenario: Inbox rows are available
- **WHEN** the GraphQL operator workflow inbox projection returns one or more
  rows
- **THEN** the console MUST show scannable rows with source summary, workflow
  status, actionability state, reason codes or blockers, allowed next actions,
  source watermark, and a clear selected-row state

#### Scenario: Inbox is empty
- **WHEN** the GraphQL operator workflow inbox projection returns no rows
- **THEN** the console MUST show an empty state that explains there are no
  operator workflow items without presenting fake work or enabled workflow
  commands

#### Scenario: Default transport is GraphQL
- **WHEN** the Phoenix-served `/operator` app shell mounts the React console
  without an injected test client
- **THEN** the console MUST read the operator workflow through the GraphQL
  product data path rather than the old JSON adapter

#### Scenario: Initial selected item reuses inbox detail
- **WHEN** the inbox projection already includes the selected row's item detail
  fields
- **THEN** the console MUST use that row as the initial selected item detail
  without immediately issuing a duplicate item-detail read for the same
  normalized event

#### Scenario: Initial packet readiness reuses selected row links
- **WHEN** the selected inbox row is already ready for packet preparation and
  includes source graph links plus required verification-check links
- **THEN** the console MUST derive the initial packet-readiness panel from the
  loaded row as prepare-packet context, without immediately issuing a duplicate
  packet-readiness read for the same graph and verification-check ids and
  without claiming the packet can already be created

#### Scenario: Item detail is selected
- **WHEN** an operator selects an inbox row whose detail is not already loaded
  or whose source watermark requires refresh
- **THEN** the console MUST fetch or reuse the selected item detail and show its
  typed identity, source context, proposed-change status, affected graph links,
  audit or revision traces, and safe next actions

#### Scenario: Item detail cannot be loaded
- **WHEN** item detail loading fails because the item is missing, unauthorized,
  stale, invalid, or the network request fails
- **THEN** the console MUST preserve the current workflow context and show an
  explicit error or blocker state instead of dropping into an ambiguous blank
  detail pane
