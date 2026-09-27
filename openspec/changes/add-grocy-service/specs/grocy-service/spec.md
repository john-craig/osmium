## Purpose

Provide a supported, persistent Grocy deployment inside Osmium MicroVMs with explicit network and lifecycle behavior.

## ADDED Requirements

### Requirement: Grocy service lifecycle
The system SHALL provide a declarative Grocy service that starts, stops, and restarts through the host's normal service supervision and uses the packaged Grocy application.

#### Scenario: Service starts in a MicroVM
- **WHEN** a MicroVM is booted with Grocy enabled
- **THEN** Grocy becomes reachable through its configured service endpoint and reports a healthy application response

### Requirement: Persistent Grocy state
The system SHALL store Grocy application state in the configured persistent service data path, separate from ephemeral MicroVM runtime state.

#### Scenario: State survives replacement
- **WHEN** a user and supported reference record are created and the MicroVM is replaced while its persistent data is retained
- **THEN** the Grocy instance exposes the same records after the replacement boots

### Requirement: Explicit network boundary
The system SHALL bind Grocy only to the configured service boundary and SHALL NOT expose its administrative or API surface through an unintended listener.

#### Scenario: Boundary is enforced
- **WHEN** the MicroVM is running
- **THEN** the configured endpoint is reachable and an unconfigured listener or address does not provide an additional Grocy access path
