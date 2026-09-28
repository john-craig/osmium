## Purpose

Provides deterministic, review-only conversion of observed LLDAP state into
secret-safe Osmium declarations for the directory's supported identity subset.

## ADDED Requirements

### Requirement: LLDAP drift conversion is runtime-derived and review-only
The system SHALL compare declared and observed supported users, groups,
memberships, enabled state, endpoint/TLS references, and consumer integration
metadata. It SHALL emit a deterministic candidate with field-level findings,
provenance, completeness, unsupported-state reporting, and unresolved
secret-file requirements. Conversion SHALL NOT mutate LLDAP, Keycloak,
Authelia, source files, ledgers, or services.

#### Scenario: Runtime directory state drifts
- **WHEN** a supported non-secret user, group, or membership is changed in a running LLDAP instance
- **THEN** drift conversion reports that exact observation and emits a candidate derived from it rather than an independently authored fixture

### Requirement: LLDAP live capture is explicit about limits
The system SHALL capture supported state from LLDAP's live GraphQL and LDAP
interfaces. It SHALL distinguish managed, unmanaged, unsupported, ambiguous,
and secret-backed state; omit password material, secrets, hashes, tokens, and
cookies; and mark the result incomplete where required state is unrepresentable
or unavailable.

#### Scenario: Unsupported LLDAP state is encountered
- **WHEN** capture encounters unsupported attributes, external state without a secret reference, or a FreeIPA-only feature
- **THEN** it records an actionable finding without inventing a declaration and marks the affected scope incomplete

### Requirement: Reverse paths are verified in dedicated MicroVM checks
The implementation SHALL provide separate booting checks named
`lldap-drift-reverse-configuration` and
`lldap-live-capture-reverse-configuration`. Their commands SHALL be `nix build
.#checks.x86_64-linux.lldap-drift-reverse-configuration --print-build-logs` and
`nix build .#checks.x86_64-linux.lldap-live-capture-reverse-configuration
--print-build-logs`.

#### Scenario: Reverse-configuration checks run
- **WHEN** either LLDAP reverse-configuration check is executed
- **THEN** it boots a MicroVM, derives a candidate from runtime observation, proves non-mutation and secret exclusion, and exercises represented candidate behavior in a replay MicroVM
