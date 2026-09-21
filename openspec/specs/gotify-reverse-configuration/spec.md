# gotify-reverse-configuration Specification

## Purpose

Provides safe, review-only conversion of observed Gotify users and applications
into declarative candidates without exposing unrecoverable passwords or tokens.

## Requirements

### Requirement: Gotify drift conversion is review-only and complete about limits

The system SHALL compare declared Gotify user and application metadata with a
runtime observation and SHALL produce deterministic, reviewable candidates and
findings for additions, removals, changes, conflicts, unsupported fields, and
unobservable secret state. It MUST not mutate Gotify, adopt records, write Nix
source, change the ledger, emit password/token values or hashes, or claim an
activatable declaration is complete when a required secret input or token output
cannot be represented.

#### Scenario: Application metadata drifts

- **WHEN** an observed managed application's name, owner, or description differs
  from its declaration
- **THEN** drift reports the field-level difference and renders a deterministic
  candidate with provenance and an explicit unresolved token-output requirement

#### Scenario: Sensitive data is observed

- **WHEN** a Gotify API response, database record, or local output contains a
  password or application token
- **THEN** drift reports only safe presence or unresolved-state metadata and
  omits the sensitive value and any reversible digest

### Requirement: Live Gotify capture is safe and explicit

The system SHALL capture supported users and applications from a running Gotify
service into a normalized, provenance-bearing observation and SHALL convert it
to a review-only candidate. It SHALL mark external users' password files and
application token outputs as operator-supplied unresolved requirements and MUST
exclude administrator records unless the operator explicitly handles them
outside automatic capture.

#### Scenario: External application is captured

- **WHEN** live capture finds a supported application created outside the local
  declarations
- **THEN** conversion emits its non-secret owner and metadata with provenance,
  requires an operator-selected token output, and does not invent or emit the
  token

#### Scenario: Repeated capture is unchanged

- **WHEN** the same running Gotify state is captured more than once
- **THEN** normalized conversion output is byte-for-byte deterministic apart
  from documented observation timestamps

### Requirement: Reverse configuration is exercised in MicroVMs

The implementation SHALL provide separate flake checks named
`gotify-drift-reverse-configuration` and `gotify-live-capture-reverse-configuration`.
Each SHALL boot and exercise Gotify in a MicroVM, derive the conversion input
from its runtime observation rather than an independently authored equivalent
fixture, verify generated candidate behavior, and verify review-only
non-mutation. The executable check commands SHALL be `nix build
.#checks.x86_64-linux.gotify-drift-reverse-configuration --print-build-logs` and
`nix build
.#checks.x86_64-linux.gotify-live-capture-reverse-configuration
--print-build-logs`.

#### Scenario: Drift conversion integration check runs

- **WHEN** the drift reverse-configuration check mutates a running Gotify
  resource and converts its runtime observation
- **THEN** the generated candidate reflects that mutation, omits secrets, and
  does not alter the running service

#### Scenario: Live capture integration check runs

- **WHEN** the live-capture reverse-configuration check creates a Gotify user or
  application outside declarations and converts the captured runtime state
- **THEN** the generated candidate reflects the external resource, retains
  provenance and incompleteness, and remains non-mutating
