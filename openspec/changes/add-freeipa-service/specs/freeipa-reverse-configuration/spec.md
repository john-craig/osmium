## Purpose

Provides deterministic, review-only conversion of supported observed FreeIPA and
LDAP-integration state into secret-safe Osmium declaration candidates.

## ADDED Requirements

### Requirement: Drift conversion covers supported directory state
The system SHALL compare declared and observed FreeIPA users, groups, group
memberships, enabled state, supported non-secret identity metadata, LDAP endpoint
metadata, TLS trust references, and Keycloak/Authelia integration declarations.
It SHALL produce a deterministic reviewable candidate derived from runtime
observation with field-level findings, provenance, completeness, unsupported-state
reporting, and unresolved runtime secret references. Conversion SHALL NOT mutate
FreeIPA, Keycloak, Authelia, source files, ledgers, or service lifecycle.

#### Scenario: Live directory state drifts
- **WHEN** a supported non-secret FreeIPA user, group, membership, or integration metadata field changes at runtime
- **THEN** drift conversion reports that exact observed difference and emits a candidate derived from the observation

#### Scenario: Secret-backed state is observed
- **WHEN** a directory password, bind password, CA private key, Kerberos key, or ticket is needed to represent observed state
- **THEN** the candidate excludes the material, reports an unresolved protected file reference where applicable, and is incomplete and not activation ready

### Requirement: Live capture is explicit about unsupported directory state
The system SHALL capture supported directory and integration state from running
FreeIPA administrative, LDAP, Kerberos, Keycloak, and Authelia interfaces with
live-system provenance. It SHALL distinguish managed, unmanaged, unsupported,
ambiguous, and secret-backed state and SHALL NOT claim completeness when required
state cannot be represented.

#### Scenario: External user is captured
- **WHEN** a supported non-secret user or group is created directly in FreeIPA
- **THEN** capture emits its observable metadata and memberships with runtime provenance and unresolved credential inputs

#### Scenario: Unsupported platform state is encountered
- **WHEN** capture finds DNS, host enrollment, service principals, HBAC/sudo, certificates, replicas, unsupported LDAP mappings, or user factor material
- **THEN** it records an actionable finding, does not invent a declaration, and marks the affected scope incomplete

### Requirement: Reverse configuration is secret-safe and verified in MicroVMs
Drift and live capture MUST NOT request, export, log, hash for output, or persist
Directory Manager or user passwords, bind passwords, private keys, Kerberos keys,
tickets, session credentials, password hashes, or authentication tokens. The
implementation SHALL provide separate booting checks named
`freeipa-drift-reverse-configuration` and
`freeipa-live-capture-reverse-configuration`; each SHALL derive its candidate
from runtime observation, prove non-mutation and secret exclusion, and exercise
the represented candidate behavior in a replay MicroVM. The commands SHALL be
`nix build .#checks.x86_64-linux.freeipa-drift-reverse-configuration
--print-build-logs` and `nix build
.#checks.x86_64-linux.freeipa-live-capture-reverse-configuration
--print-build-logs`.

#### Scenario: Reverse-configuration checks run
- **WHEN** either dedicated FreeIPA reverse-configuration check is executed
- **THEN** it boots a MicroVM, derives a candidate from runtime state, proves the source remains unchanged, and verifies represented behavior or explicit incompleteness
