## Purpose

Provide safe, review-only conversion of Homebox runtime observations and drift into declarations while preserving the boundaries around secrets, database coupling, and inventory history.

## ADDED Requirements

### Requirement: Drift conversion is non-mutating
The system SHALL detect supported Homebox drift and produce a reviewable conversion without mutating Homebox, the declaration, ownership state, or database contents.

#### Scenario: Drift conversion leaves Homebox unchanged
- **WHEN** an administrator requests conversion for supported drift
- **THEN** the command returns proposed declaration changes and the Homebox database remains unchanged

### Requirement: Live capture uses runtime observation
The system SHALL generate live-capture declarations from a running Homebox instance or its explicitly selected compatible runtime database state, not from an independently authored equivalent fixture.

#### Scenario: Captured metadata reflects runtime state
- **WHEN** a supported tag or template is changed through Homebox and live capture is requested
- **THEN** the generated declaration contains the changed runtime value and its source provenance

### Requirement: Reverse configuration reports limits
The system SHALL identify ownership gaps, ambiguous identities, unsupported schema versions, secret omission, excluded inventory/history, and incomplete relationships in drift and live-capture results.

#### Scenario: Credentials are omitted
- **WHEN** reverse configuration encounters a password, OIDC secret, session token, invitation token, or raw API key
- **THEN** it omits the value, identifies the required runtime input, and does not claim completeness

#### Scenario: Unsupported database state is reported
- **WHEN** live capture cannot safely interpret the running Homebox schema
- **THEN** it returns an explicit unsupported/incomplete result without guessing or mutating the database

### Requirement: Reverse-configuration MicroVM coverage
The system SHALL provide separate executable MicroVM integration tests for drift conversion and live capture conversion, and each SHALL verify runtime observation and resulting declaration behavior.

#### Scenario: Drift conversion integration test
- **WHEN** the drift test boots Homebox, changes supported metadata through the running service, and invokes drift conversion
- **THEN** it verifies the generated declaration contains the observed change and Homebox was not mutated by conversion

#### Scenario: Live capture integration test
- **WHEN** the live-capture test boots Homebox, creates or changes supported identities or metadata, and invokes live capture
- **THEN** it verifies the generated declaration came from runtime observation and reproduces the supported resulting behavior
