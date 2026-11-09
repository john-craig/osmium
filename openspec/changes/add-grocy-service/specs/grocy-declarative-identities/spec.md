## Purpose

Manage Grocy users and their API access declaratively without placing passwords or API-token material in the Nix store.

## ADDED Requirements

### Requirement: Declarative user reconciliation
The system SHALL reconcile declared Grocy users by stable declaration identity, SHALL preserve unmanaged users, SHALL reject ambiguous matches, and SHALL avoid destructive deletion by default.

#### Scenario: User is created once
- **WHEN** a declared user is absent and the service has started
- **THEN** the service creates the user, records its instance-local identity in an ownership ledger, and does not create a duplicate on later activations

#### Scenario: Ambiguous user identity fails closed
- **WHEN** a declaration matches multiple Grocy users and no ownership record disambiguates them
- **THEN** reconciliation reports the ambiguity and does not update or delete any matched user

#### Scenario: Unmanaged user is preserved
- **WHEN** Grocy contains a user not owned by the declaration
- **THEN** reconciliation leaves that user unchanged

### Requirement: Runtime-only user credentials
The system SHALL consume declared user password material only at runtime from protected secret files or equivalent runtime inputs and SHALL NOT embed password values in evaluated configuration, generated service files, logs, or reverse-configuration output.

#### Scenario: Password bootstrap uses a secret file
- **WHEN** a declared user is missing and its runtime password secret is available
- **THEN** the user is created using the secret at runtime and the secret is absent from the Nix store and generated declaration

### Requirement: Per-user API token lifecycle
The system SHALL support one owned API token per declared user, SHALL persist successful bootstrap state, SHALL not regenerate an unchanged token on every activation, and SHALL rotate the token when the configured secret-file value changes.

#### Scenario: Token is bootstrapped once
- **WHEN** a declared user has no owned API token and token bootstrap is enabled
- **THEN** the service creates one token at runtime, stores or exposes it through a protected secret path, and subsequent activations reuse it

#### Scenario: Changed token secret triggers rotation
- **WHEN** the configured replacement token secret-file value changes
- **THEN** the service consumes the replacement at runtime, replaces the owned token, and does not expose either secret in logs or the Nix store

#### Scenario: Token ownership is missing
- **WHEN** the service cannot prove that an existing token belongs to the declaration
- **THEN** it does not revoke or replace that token automatically and reports an actionable failure

### Requirement: Identity reverse configuration
The system SHALL provide review-only drift conversion and live-system capture for supported users and token declarations while omitting passwords and token values and marking output incomplete when required identity or secret state cannot be represented.

#### Scenario: Identity drift produces a declaration
- **WHEN** a running Grocy identity differs from the declared user or token configuration
- **THEN** drift detection produces a reviewable declaration conversion describing the observed difference without mutating Grocy or including secret material

#### Scenario: Live identity capture is secret-safe
- **WHEN** live capture reads Grocy users and owned token metadata
- **THEN** it produces a reviewable declaration with provenance and explicit placeholders or incompleteness for password and token secret inputs
