## ADDED Requirements

### Requirement: WorkOS success responses are bounded during receipt

Office Graph SHALL enforce the WorkOS SSO success-response byte limit in the production HTTP transport while the body is received rather than only after the complete response has been buffered.

#### Scenario: WorkOS success response exceeds the byte limit

- **WHEN** the configured WorkOS token endpoint sends a successful response whose declared or accumulated body size exceeds the configured maximum
- **THEN** the production adapter MUST stop receiving that response, MUST NOT return the oversized body to the SSO decoder, and MUST fail the exchange as provider unavailable

#### Scenario: WorkOS success response is within the byte limit

- **WHEN** the configured WorkOS token endpoint sends a complete successful response within the maximum size and timeout
- **THEN** the production adapter MUST return the original status, normalized headers, and exact bounded body to the SSO decoder
