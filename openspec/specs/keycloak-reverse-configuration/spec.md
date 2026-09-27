# keycloak-reverse-configuration Specification

## Purpose

Provides deterministic, review-only conversion of declared drift and captured
live Keycloak state into secret-safe Osmium declaration candidates.

## Requirements

### Requirement: Drift conversion covers supported declarative attributes

The system SHALL compare declared and observed Keycloak realms, key-provider
metadata, clients, scopes, roles, groups, users, mappings, and non-secret
credential state. It SHALL produce a deterministic, reviewable Osmium candidate
derived from the runtime observation, with field-level findings, provenance,
completeness, unsupported-state reporting, and unresolved secret-file
requirements. Conversion SHALL NOT mutate Keycloak, source files, ledgers, or
running services.

#### Scenario: Runtime state drifts from the declaration

- **WHEN** a supported non-secret client, role, group, user, mapping, or key
  metadata field is changed in the running Keycloak instance
- **THEN** drift conversion reports that exact runtime difference and emits a
  candidate based on the observation rather than an independently authored
  equivalent fixture

#### Scenario: Drift includes secret-backed state

- **WHEN** an observed user, client, administrator, TLS, database, or signing-key
  resource requires secret material
- **THEN** the candidate contains an unresolved file-reference requirement,
  excludes secret bytes and hashes, and is marked incomplete and not activation
  ready

### Requirement: Live capture covers supported declarative attributes

The system SHALL read supported state from a running Keycloak administrative API
and protocol endpoints and SHALL produce a deterministic declaration candidate
for realms, clients, scopes, roles, groups, users, mappings, and public
signing-key metadata. Capture SHALL distinguish local, federated, unmanaged,
unsupported, ambiguous, and secret-backed state and SHALL NOT claim completeness
when required state cannot be represented.

#### Scenario: External realm state is captured

- **WHEN** supported resources are created directly in the running Keycloak
  instance
- **THEN** capture emits their observable non-secret attributes with live-system
  provenance and explicit unresolved inputs

#### Scenario: Unsupported state is encountered

- **WHEN** capture encounters identity federation, custom providers, unknown
  protocol mappers, external key storage, or another unsupported resource
- **THEN** it records an actionable finding, omits invented configuration, and
  marks the affected scope incomplete

### Requirement: Reverse configuration is secret-safe and non-mutating

Drift and live capture MUST NOT request, export, log, hash for output, or persist
administrator passwords, user passwords, client secrets, private signing keys,
database passwords, TLS private keys, session cookies, authorization codes, or
tokens. Commands SHALL be read-only against Keycloak and SHALL write only to an
operator-selected output path or standard output.

#### Scenario: Secret leakage is checked

- **WHEN** reverse configuration observes resources backed by known test secrets
- **THEN** no secret value or reversible derivative appears in stdout, stderr,
  generated candidates, provenance, findings, or persisted observation state

#### Scenario: Conversion completes

- **WHEN** a candidate is generated from drift or live capture
- **THEN** Keycloak resources, reconciliation ledgers, source files, and service
  lifecycle state remain unchanged

### Requirement: Reverse paths are verified in dedicated MicroVM checks

The implementation SHALL provide separate booting checks named
`keycloak-drift-reverse-configuration` and
`keycloak-live-capture-reverse-configuration`. Each check SHALL derive its
candidate from runtime-observed state, prove non-mutation and secret exclusion,
and exercise the represented candidate behavior in a replay MicroVM. The
commands SHALL be `nix build
.#checks.x86_64-linux.keycloak-drift-reverse-configuration
--print-build-logs` and `nix build
.#checks.x86_64-linux.keycloak-live-capture-reverse-configuration
--print-build-logs`.

#### Scenario: Drift reverse check runs

- **WHEN** the drift reverse-configuration check is executed
- **THEN** it mutates live non-secret Keycloak state, converts that observation,
  and verifies the replayed declaration behavior

#### Scenario: Live-capture reverse check runs

- **WHEN** the live-capture reverse-configuration check is executed
- **THEN** it creates external live resources, captures those resources, and
  verifies the candidate's represented behavior and explicit incompleteness
