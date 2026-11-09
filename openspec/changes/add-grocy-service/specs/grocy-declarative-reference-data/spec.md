## Purpose

Manage a bounded set of stable Grocy reference entities declaratively while preserving household-owned records outside the declaration.

## ADDED Requirements

### Requirement: Supported reference entities
The system SHALL support declarative reconciliation of Grocy locations, quantity units, quantity-unit conversions, product groups, and shopping locations.

#### Scenario: Reference data is created in dependency order
- **WHEN** a declaration contains missing supported reference entities
- **THEN** reconciliation creates them in an order that satisfies their foreign-key dependencies

### Requirement: Ownership-safe reference reconciliation
The system SHALL use stable declaration identities plus an ownership ledger for supported reference entities, SHALL reject ambiguous natural-key matches, SHALL preserve unmanaged records, and SHALL not delete records by default.

#### Scenario: Existing owned record is updated
- **WHEN** a supported reference entity has an ownership record and declared attributes changed
- **THEN** reconciliation updates only that owned record

#### Scenario: Duplicate natural keys fail closed
- **WHEN** a declaration's natural key matches multiple records
- **THEN** reconciliation reports the ambiguity and performs no update or deletion

#### Scenario: Unmanaged reference data is preserved
- **WHEN** Grocy contains a supported reference record absent from the declaration and ownership ledger
- **THEN** reconciliation leaves it unchanged

### Requirement: Operational data is excluded
The system SHALL NOT declaratively replay or reconcile products, barcodes, recipes, recipe positions, chore/task definitions, stock, shopping-list contents, execution history, consumption, transfers, inventory bookings, or other transactional Grocy state.

#### Scenario: Transactional state is not replayed
- **WHEN** the service activates with an unchanged declaration after Grocy has recorded operational activity
- **THEN** activation does not create duplicate stock, shopping-list, consumption, completion, or execution events

### Requirement: Reference-data reverse configuration
The system SHALL provide review-only drift conversion and live-system capture for supported reference attributes, including provenance, completeness, unsupported-state reporting, and secret-safe non-mutating behavior.

#### Scenario: Reference drift is convertible
- **WHEN** an owned supported reference entity differs from its declaration
- **THEN** drift detection produces a reviewable Mythoclast declaration conversion describing the observed attributes without changing Grocy

#### Scenario: Live capture reads runtime reference data
- **WHEN** live capture queries a running Grocy instance
- **THEN** it generates a reviewable declaration from the runtime observation, preserves provenance, and marks the result incomplete if relationships or fields cannot be represented
