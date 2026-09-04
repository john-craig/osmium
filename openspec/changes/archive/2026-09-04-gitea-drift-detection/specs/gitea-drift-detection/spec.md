## Purpose

Provides a reliable, read-only account of divergence between declarative Gitea
identity configuration and the identities currently present in the service.

## ADDED Requirements

### Requirement: Observed Gitea identities are collected read-only

The system SHALL collect users and organizations from the running Gitea
instance through supported read-only administrative interfaces. Collection
SHALL handle pagination and SHALL fail clearly when the instance or an API
request is unavailable. Collection SHALL NOT create, modify, delete, or transfer
Gitea records.

#### Scenario: Collect current identities

- **WHEN** Gitea is available and the inspector is run
- **THEN** it returns normalized users and organizations from all result pages without changing Gitea state

#### Scenario: Gitea is unavailable

- **WHEN** the inspector cannot reach Gitea or an administrative request fails
- **THEN** it reports an operational error and does not emit a successful drift result

#### Scenario: Multiple result pages exist

- **WHEN** users or organizations exceed one API page
- **THEN** the inspector follows every page and includes each observed record exactly once

### Requirement: Supported drift is classified

The system SHALL compare observed identities with declared users and
organizations using only supported non-secret fields. It SHALL classify at
least matching, missing, changed, unmanaged, administrator-conflict, and
ownership-conflict states. A record that cannot be safely classified SHALL be
reported as ambiguous or unobservable rather than silently treated as matching.

#### Scenario: Declared identity matches

- **WHEN** all compared observed fields equal the declaration
- **THEN** the result classifies the identity as matching

#### Scenario: External user is created

- **WHEN** Gitea contains a user with no corresponding declaration
- **THEN** the result classifies that user as unmanaged and includes its stable identity and supported profile fields

#### Scenario: Declared metadata changes out of band

- **WHEN** an observed email or supported profile field differs from its declaration
- **THEN** the result classifies the identity as changed and identifies the differing fields

#### Scenario: Administrator conflicts with a non-admin declaration

- **WHEN** an observed administrator has the username of a declared non-admin user
- **THEN** the result classifies an administrator conflict and does not recommend demotion or adoption

#### Scenario: Organization owner differs

- **WHEN** an observed organization owner does not match its declared owner
- **THEN** the result classifies an ownership conflict and does not recommend ownership transfer

### Requirement: Reports are safe and automation-friendly

The system SHALL provide a machine-readable report and a human-readable report.
Reports SHALL omit passwords, password hashes, access tokens, SSH private keys,
and other credential material. Check mode SHALL use a nonzero exit status when
drift or an operational error is present and SHALL use zero only for a complete
successful check with no drift.

#### Scenario: Machine-readable report is requested

- **WHEN** an operator requests JSON output
- **THEN** the output contains a stable schema with observation time, status, classifications, and sanitized field differences

#### Scenario: Secret material is encountered

- **WHEN** observed API data or local configuration contains credential-related fields
- **THEN** those fields are excluded from the report and generated diagnostics

#### Scenario: No drift exists

- **WHEN** collection succeeds and every compared record matches
- **THEN** check mode exits successfully and reports a clean result

### Requirement: Observation history is non-secret and non-authoritative

When observation history is enabled, the system SHALL persist only sanitized
fingerprints, timestamps, and schema/version metadata. History SHALL be used to
identify that an observed snapshot changed, but SHALL NOT replace comparison
against the current declarative configuration or authorize mutations.

#### Scenario: Snapshot changes

- **WHEN** a new normalized snapshot differs from the previous fingerprint
- **THEN** the report identifies an observed-state change without persisting raw credentials or authorizing reconciliation

#### Scenario: Inspector runs repeatedly without mutation

- **WHEN** the same Gitea state is inspected repeatedly
- **THEN** the result remains stable and no Gitea record is modified

### Requirement: Drift detection is exercised in a MicroVM

The Gitea MicroVM integration test SHALL create and modify records outside the
declarative configuration, run the inspector, and verify classifications,
secret omission, read-only behavior, and failure handling against the running
Gitea version.

#### Scenario: External user mutation is detected

- **WHEN** an unmanaged user is created in the running MicroVM
- **THEN** the inspector reports that user as unmanaged without deleting or modifying it

#### Scenario: External metadata mutation is detected

- **WHEN** supported metadata for a declared identity is changed out of band
- **THEN** the inspector reports changed fields and leaves the mutation intact

#### Scenario: Inspection is read-only

- **WHEN** the inspector runs against users and organizations
- **THEN** record identifiers, ownership, metadata, and database state remain unchanged
