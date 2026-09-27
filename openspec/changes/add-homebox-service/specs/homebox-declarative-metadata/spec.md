## Purpose

Manage Homebox collection-scoped organizational metadata declaratively without treating household inventory or history as replayable configuration.

## ADDED Requirements

### Requirement: Supported collection metadata
The system SHALL support declarative reconciliation of tags, tag hierarchies, entity types, entity templates, and typed template fields within owned Homebox groups.

#### Scenario: Metadata is created in dependency order
- **WHEN** a declaration contains missing tags, entity types, or templates
- **THEN** reconciliation creates them in an order that satisfies parent and template/type references

### Requirement: Ownership-safe metadata reconciliation
The system SHALL use retained UUID ownership mappings or an explicit adoption mapping, SHALL reject ambiguous name matches, SHALL preserve unmanaged metadata, and SHALL not delete metadata by default.

#### Scenario: Owned metadata is updated
- **WHEN** an owned tag, entity type, or template differs from its declaration
- **THEN** reconciliation updates only the owned record and verifies the resulting references

#### Scenario: Ambiguous metadata fails closed
- **WHEN** a declaration's name or hierarchy matches multiple records without an ownership mapping
- **THEN** reconciliation reports the ambiguity and performs no update or deletion

### Requirement: Inventory and history are excluded
The system SHALL NOT declaratively create, update, delete, or replay inventory entities, attachments, maintenance entries, imports, exports, duplicate actions, notifiers, barcode lookups, or bulk actions.

#### Scenario: Inventory activity is not replayed
- **WHEN** Homebox contains inventory or maintenance changes between activations
- **THEN** activation does not create duplicate entities, attachments, maintenance records, or asynchronous jobs

### Requirement: Metadata reverse configuration
The system SHALL provide review-only drift conversion and live capture for supported metadata attributes, including provenance, ownership, unsupported-state reporting, and completeness status.

#### Scenario: Runtime metadata is captured
- **WHEN** a supported tag, entity type, or template is changed through Homebox
- **THEN** live capture generates a declaration containing the observed runtime value rather than an independently authored fixture
