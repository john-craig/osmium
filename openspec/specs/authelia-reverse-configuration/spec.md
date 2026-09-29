# authelia-reverse-configuration Specification

## Purpose

Provides deterministic, review-only conversion of supported observed Authelia
state into secret-safe Osmium declaration candidates.

## Requirements

### Requirement: Drift conversion covers supported declarative attributes
The system SHALL compare declared and observed local-user metadata, group
membership, password and TOTP status, TOTP policy, storage mode, and
access-control policy. It SHALL produce a deterministic reviewable candidate
derived from runtime observation with field-level findings, provenance,
completeness, unsupported-state reporting, and unresolved runtime secret-file
references. Conversion SHALL NOT mutate Authelia, the file backend, SQLite state,
ledgers, source files, or service lifecycle.

#### Scenario: Runtime policy or identity state drifts
- **WHEN** supported non-secret user metadata, group membership, TOTP policy, or access-control state changes in the running service
- **THEN** drift conversion reports that exact observed difference and generates a candidate from the observation

#### Scenario: Secret-backed state is observed
- **WHEN** an observed user, storage configuration, session configuration, or TOTP factor requires secret material
- **THEN** the candidate excludes that material, requires an unresolved runtime file reference where applicable, and is marked incomplete and not activation ready

### Requirement: Live capture is safe and explicit about limits
The system SHALL capture supported state from the running Authelia service, its
managed file backend, storage tooling, and service facts with live-system
provenance. It SHALL distinguish managed, unmanaged, user-enrolled, unsupported,
ambiguous, and secret-backed state and SHALL NOT claim completeness when a needed
attribute cannot be safely represented.

#### Scenario: Externally created supported state is captured
- **WHEN** an operator creates supported non-secret identity or policy state in the live system
- **THEN** capture emits its observable attributes with runtime provenance and unresolved secret inputs

#### Scenario: Unsupported factor or backend is encountered
- **WHEN** capture encounters WebAuthn, Duo, LDAP, external database state, unknown user attributes, or unavailable source inputs
- **THEN** it records an actionable finding, does not invent a declaration, and marks the affected scope incomplete

### Requirement: Reverse configuration is secret-safe and non-mutating
Drift and live capture MUST NOT request, export, log, hash for output, or persist
plaintext passwords, password hashes, storage or session keys, identity-validation
keys, TOTP secrets, enrollment URIs, QR data, cookies, or authentication tokens.
Commands SHALL only read live state and write a report or candidate to standard
output or an operator-selected output path.

#### Scenario: Secret leakage is checked
- **WHEN** reverse configuration runs against known test credentials and TOTP material
- **THEN** none of those values or reversible derivatives occur in its output, findings, provenance, or persistent observation state

### Requirement: Reverse paths use dedicated MicroVM checks
The implementation SHALL provide separate booting checks named
`authelia-drift-reverse-configuration` and
`authelia-live-capture-reverse-configuration`. Each check SHALL derive its
candidate from runtime-observed state, prove non-mutation and secret exclusion,
and exercise represented candidate behavior in a replay MicroVM. The commands
SHALL be `nix build .#checks.x86_64-linux.authelia-drift-reverse-configuration
--print-build-logs` and `nix build
.#checks.x86_64-linux.authelia-live-capture-reverse-configuration
--print-build-logs`.

#### Scenario: Reverse-configuration checks run
- **WHEN** either dedicated reverse-configuration check is executed
- **THEN** it boots a MicroVM, derives its candidate from runtime state, proves the source was not mutated, and verifies represented behavior or explicit incompleteness
