## Purpose

Provides secret-safe, review-only drift detection and live capture for supported Paperless users, permissions, and API-token metadata.

## ADDED Requirements

### Requirement: Paperless drift observation is complete about secrets and ownership
The system SHALL observe supported local user metadata, groups, permissions, managed-token identity/presence, and ownership-ledger state from the running Paperless service. Observations SHALL include deterministic ordering, provenance, supported attributes, unsupported or ambiguous findings, and completeness without mutating Paperless, documents, source declarations, runtime secret files, or ledgers.

#### Scenario: Managed user metadata drifts
- **WHEN** a supported managed user’s active, staff, group, or permission metadata changes in the running Paperless service
- **THEN** drift reports the field-level difference and its runtime provenance without changing the service or declaration source

#### Scenario: Token value is observed
- **WHEN** a Paperless API response or local database contains a token value
- **THEN** observation reports only token presence, ownership, and unresolved output state and emits neither the token nor a reversible digest

### Requirement: Live capture produces incomplete candidates for unrecoverable inputs
The system SHALL convert supported runtime users, groups, permissions, and token metadata into a review-only candidate derived from live observation. Candidates SHALL omit passwords, password hashes, API-token values, secret keys, database/broker credentials, and document contents; require operator-supplied password files and token output paths; and mark `complete` and activation readiness false whenever omitted or unsupported state prevents safe replay.

#### Scenario: External user and token are captured
- **WHEN** live capture finds a Paperless user and token created outside the declaration
- **THEN** the candidate contains non-secret identity and permission metadata with runtime provenance, requires operator-selected secret/output paths, and does not claim activation readiness

### Requirement: Reverse configuration is exercised in dedicated MicroVM checks
The system SHALL expose separate checks named `paperless-drift-reverse-configuration` and `paperless-live-capture-reverse-configuration`. Each SHALL boot and exercise Paperless in a MicroVM, derive conversion input from runtime observation rather than an independently authored equivalent fixture, prove source non-mutation, exclude secrets, and validate replay of complete represented behavior or explicit incompleteness.

#### Scenario: Drift reverse-configuration check executes
- **WHEN** `nix build .#checks.x86_64-linux.paperless-drift-reverse-configuration --print-build-logs` runs
- **THEN** it boots a source MicroVM, changes supported live identity state, derives a candidate from observation, proves non-mutation, and validates replay or exact blockers

#### Scenario: Live-capture reverse-configuration check executes
- **WHEN** `nix build .#checks.x86_64-linux.paperless-live-capture-reverse-configuration --print-build-logs` runs
- **THEN** it boots a source MicroVM, creates external users and token metadata, captures runtime-derived state, proves source safety, and validates replay or explicit incompleteness
