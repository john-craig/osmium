## Purpose

Provides secret-safe, review-only runtime observation and candidate conversion for supported NocoDB Community Edition declarations.

## ADDED Requirements

### Requirement: Drift observation is complete only for representable managed state
The system SHALL inspect the running NocoDB Community Edition service and compare supported workspace, local user, API-token metadata, membership, base, table, field, relation, view, and managed-record state against declarations. Observations SHALL include deterministic ordering, resource ownership, provenance, supported attributes, unsupported/ambiguous findings, and completeness status without mutating NocoDB, source declarations, runtime secrets, or ledgers.

#### Scenario: Runtime drift produces a reviewable observation
- **WHEN** a supported non-secret managed field or view is changed through the running NocoDB API
- **THEN** drift observation reports the runtime difference with ownership and provenance while leaving the source service unchanged

### Requirement: Live capture produces secret-safe, incomplete candidates when necessary
The system SHALL capture representable Community Edition runtime state into a review-only candidate declaration derived from that observation. Candidates SHALL omit passwords, minted token values, JWT material, database credentials, attachment secrets, and generated identifiers; API-token metadata SHALL identify its unavailable runtime output path and any unrepresentable scope/restriction as unresolved. Candidates SHALL mark unresolved runtime-only inputs and unsupported/licensed-only state, and set `complete` and activation readiness false whenever omitted information prevents safe replay.

#### Scenario: External runtime base is captured
- **WHEN** an external base, schema, view, and record are created in the running Community Edition service
- **THEN** live capture derives a candidate from the observed runtime resources, records provenance, excludes secrets, and does not claim readiness if required credentials or unsupported attributes cannot be represented

### Requirement: Candidate conversion is non-mutating and behaviorally verified
The system SHALL provide separate drift and live-capture MicroVM checks that prove candidate conversion does not mutate the source NocoDB service or its ownership ledger. Each check SHALL boot a replay MicroVM and verify all complete represented non-secret declarations reproduce their observed runtime behavior; incomplete candidates SHALL instead identify their exact blockers.

#### Scenario: Drift reverse-configuration check executes
- **WHEN** `nix build .#checks.x86_64-linux.nocodb-drift-reverse-configuration --print-build-logs` runs
- **THEN** it boots a source MicroVM, creates live drift, derives a candidate from observation, proves source non-mutation, and verifies replay or explicit incompleteness

#### Scenario: Live-capture reverse-configuration check executes
- **WHEN** `nix build .#checks.x86_64-linux.nocodb-live-capture-reverse-configuration --print-build-logs` runs
- **THEN** it boots a source MicroVM, captures externally created runtime state, proves the candidate was runtime-derived and source-safe, and verifies replay or explicit incompleteness
