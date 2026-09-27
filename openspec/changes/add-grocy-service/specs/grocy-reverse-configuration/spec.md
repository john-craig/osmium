## Purpose

Expose safe, review-only conversions from Grocy runtime state and detected drift into declarations without pretending that secrets or transactional state are portable.

## ADDED Requirements

### Requirement: Drift conversion is review-only
The system SHALL detect supported Grocy declaration drift and produce a reviewable conversion without mutating Grocy, the declaration, or persistent ownership state.

#### Scenario: Drift conversion does not mutate
- **WHEN** an administrator requests conversion for supported drift
- **THEN** the command returns a proposed declaration and leaves the running service and source declaration unchanged

### Requirement: Live capture uses runtime observation
The system SHALL capture supported users and reference attributes from a running Grocy instance and SHALL generate output from those observations rather than from an independently authored equivalent fixture.

#### Scenario: Captured value reflects runtime state
- **WHEN** a supported reference value is changed through Grocy's API and live capture is requested
- **THEN** the generated declaration contains the changed runtime value

### Requirement: Reverse configuration is explicit about limits
The system SHALL identify provenance, unsupported or ambiguous state, ownership gaps, secret omission, and incomplete relationships in every drift or live-capture result.

#### Scenario: Secret state is omitted
- **WHEN** reverse configuration encounters a password or API-token value
- **THEN** it omits the value, identifies the required runtime secret input, and does not claim the declaration is complete

#### Scenario: Unsupported operational state is reported
- **WHEN** live capture observes excluded transactional or operational data
- **THEN** the result reports that state as unsupported or excluded rather than converting it into replayable declarations

### Requirement: Reverse-configuration MicroVM coverage
The system SHALL provide separate executable MicroVM integration tests for drift conversion and live capture conversion, and each test SHALL verify both runtime observation and resulting declaration behavior.

#### Scenario: Drift conversion integration test
- **WHEN** the drift conversion MicroVM test boots Grocy, changes a supported entity through the running service, and invokes drift conversion
- **THEN** the test verifies the generated declaration contains the observed change and the conversion did not mutate the source service

#### Scenario: Live capture integration test
- **WHEN** the live-capture MicroVM test boots Grocy, creates or changes supported runtime data through Grocy, and invokes live capture
- **THEN** the test verifies the generated declaration came from runtime observation and can reproduce the supported resulting behavior
