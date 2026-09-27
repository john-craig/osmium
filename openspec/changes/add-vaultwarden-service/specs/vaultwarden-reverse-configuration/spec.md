## Purpose

Provides deterministic, review-only conversion of Vaultwarden drift and live
state into secret-safe Osmium declaration candidates.

## ADDED Requirements

### Requirement: Drift conversion covers supported Vaultwarden declarations

The system SHALL compare declared and observed users, organizations,
collections, memberships, non-secret metadata, credential status, and
organization-cipher identities. It SHALL derive candidates from runtime
observations with field-level findings, provenance, completeness, unsupported
state, and unresolved runtime-file references. It SHALL NOT mutate Vaultwarden,
source files, ledgers, or services.

#### Scenario: Organization state drifts

- **WHEN** a supported organization, collection, membership, or non-secret user
  attribute changes in the running service
- **THEN** drift conversion reports the observed difference and emits a
  reviewable candidate based on that runtime state

#### Scenario: Encrypted or personal-vault state drifts

- **WHEN** observation finds organization cipher payloads or personal-vault
  items that cannot be safely represented
- **THEN** conversion records an explicit unresolved or unsupported finding,
  excludes plaintext and sensitive ciphertext from output, and marks the
  candidate incomplete where required

### Requirement: Live capture preserves provenance and incompleteness

The system SHALL capture supported state from a running Vaultwarden API and
classify managed, unmanaged, invited, external, ambiguous, personal-vault, and
encrypted-payload state. It MUST NOT invent master passwords, organization keys,
encrypted cipher payloads, or runtime source paths. Missing secret-backed inputs
MUST make the affected candidate incomplete and not activation-ready.

#### Scenario: External organization is captured

- **WHEN** an organization, collection, or membership is created directly
  through the running Vaultwarden service
- **THEN** live capture emits its observable non-secret attributes with runtime
  provenance and explicit ownership status

#### Scenario: Required encrypted input is unavailable

- **WHEN** capture observes an organization cipher whose encrypted payload cannot
  be exported safely or whose source file is unavailable
- **THEN** capture records the limitation and does not claim a complete
  replayable cipher declaration

### Requirement: Reverse configuration is non-mutating and secret-safe

Drift and live capture MUST NOT request, export, log, hash for output, or persist
user master passwords, password hashes, access tokens, session cookies,
organization keys, plaintext vault secrets, or reversible derivatives. Commands
SHALL write only to an operator-selected output path or standard output and
SHALL preserve the running service and its ownership ledger.

#### Scenario: Reverse output excludes vault secrets

- **WHEN** reverse configuration observes known test users and encrypted
  organization ciphers
- **THEN** no plaintext secret, password, key, token, or sensitive ciphertext
  appears in candidates, findings, provenance, logs, or persisted observations

#### Scenario: Reverse conversion completes

- **WHEN** a candidate is generated from drift or live capture
- **THEN** Vaultwarden resources, source files, ledgers, and service lifecycle
  state remain unchanged

### Requirement: Reverse paths are verified in dedicated MicroVM checks

The implementation SHALL provide separate booting checks named
`vaultwarden-drift-reverse-configuration` and
`vaultwarden-live-capture-reverse-configuration`. Each check SHALL derive its
candidate from runtime-observed state, prove non-mutation and secret exclusion,
and verify represented user, organization, membership, and collection behavior
after explicit unresolved inputs are supplied. The executable commands SHALL be
`nix build .#checks.x86_64-linux.vaultwarden-drift-reverse-configuration
--print-build-logs` and `nix build
.#checks.x86_64-linux.vaultwarden-live-capture-reverse-configuration
--print-build-logs`.

#### Scenario: Drift reverse check runs

- **WHEN** the drift reverse-configuration check executes after mutating live
  non-secret organization state
- **THEN** the candidate reflects that exact runtime observation and replayed
  represented behavior succeeds without mutating the source instance

#### Scenario: Live-capture reverse check runs

- **WHEN** the live-capture check creates external users, organizations, and
  memberships through the running API
- **THEN** capture proves runtime provenance, explicit incompleteness for
  unavailable encrypted inputs, secret exclusion, and non-mutation
