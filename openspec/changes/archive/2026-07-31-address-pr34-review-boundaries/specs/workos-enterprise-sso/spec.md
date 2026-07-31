## ADDED Requirements

### Requirement: WorkOS non-success responses are bounded during receipt

Office Graph SHALL enforce the WorkOS SSO response byte limit in the production HTTP transport while non-success response bodies are received rather than only after the complete response has been buffered.

#### Scenario: WorkOS non-success response exceeds the byte limit

- **WHEN** the configured WorkOS token endpoint sends a non-success response whose declared or accumulated body size exceeds the configured maximum
- **THEN** the production adapter MUST stop receiving that response before buffering the complete body and MUST fail the exchange as provider unavailable

#### Scenario: WorkOS non-success response is within the byte limit

- **WHEN** the configured WorkOS token endpoint sends a complete non-success response within the maximum size and timeout
- **THEN** the production adapter MUST return the original status, normalized headers, and exact bounded body to the SSO decoder

### Requirement: WorkOS connection storage failures remain retryable

Office Graph SHALL distinguish a missing or disabled enterprise connection from a storage failure while loading that connection for WorkOS login.

#### Scenario: Active connection lookup storage fails

- **WHEN** WorkOS login preparation or code exchange cannot load the active enterprise connection because the Ash persistence layer is unavailable
- **THEN** Office Graph MUST return the bounded transient enterprise identity storage failure rather than classifying the identity or connection as unavailable
