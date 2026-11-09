## Purpose

Provides a native, persistent Authelia authentication portal whose loopback-only
endpoints are securely published by an external TLS-terminating reverse proxy.

## ADDED Requirements

### Requirement: Authelia runs as a native Osmium service
The system SHALL provide a disabled-by-default `services.osmium.authelia` service
using the pinned Nixpkgs Authelia package and SHALL NOT use a mutable container
image or runtime package download. It SHALL expose typed settings for the public
portal URL, loopback guest listener, host diagnostic forwarding, state path, and
runtime secret files.

#### Scenario: Enabled service becomes ready
- **WHEN** an operator enables Authelia with a valid declaration and required runtime inputs
- **THEN** the native service starts and its loopback health and authorization endpoints respond

#### Scenario: Invalid service configuration is rejected
- **WHEN** the declaration has an unsafe state path, invalid portal URL, exposed raw listener, colliding port, or missing required runtime input
- **THEN** evaluation or readiness fails with an actionable diagnostic and the service is not available unauthenticated

### Requirement: State and secret material have distinct lifecycles
The system SHALL persist the SQLite database, managed file-backend state, and
secret-free reconciliation state across impermanent guest recreation. Storage
encryption, session, and identity-validation key material SHALL be supplied only
through protected runtime files and SHALL NOT appear in the Nix store, generated
Nix configuration, command arguments, journals, ledgers, observations, or
readiness output. A changed required secret file SHALL trigger a validated reload
or restart; an invalid replacement MUST leave the last valid persisted state
usable.

#### Scenario: State survives recreation
- **WHEN** users and second-factor state exist and the MicroVM guest root is recreated
- **THEN** the service restores the same managed identity and SQLite state without recreating credentials or factors

#### Scenario: Required key replacement is invalid
- **WHEN** an enabled runtime key file is replaced with an empty, unreadable, or invalid value
- **THEN** the replacement is rejected without exposing its content or overwriting the last valid service state

### Requirement: External TLS proxy owns the public boundary
The Authelia listener and proxy-authorization endpoint SHALL bind only to
loopback. The module SHALL require an HTTPS public portal URL, document the
external proxy's TLS and required forwarded-header responsibilities, and SHALL
NOT configure TLS certificates, public virtual hosts, protected routes, or an
Osmium-owned reverse proxy. The service SHALL trust forwarded request metadata
only from the local proxy boundary.

#### Scenario: Direct network access is denied
- **WHEN** a host or peer reaches the guest without the external TLS reverse proxy
- **THEN** no raw Authelia portal or proxy-authorization listener is reachable over the guest network

#### Scenario: Local proxy metadata is accepted
- **WHEN** a loopback proxy sends the required HTTPS and request-destination forwarded headers
- **THEN** Authelia evaluates the request against the declared public portal and access-control policy

### Requirement: Service lifecycle is exercised in a MicroVM
The implementation SHALL provide a booting `authelia` flake check that starts the
service, uses live portal and authorization endpoints, verifies loopback-only
networking, runtime-secret exclusion, and persistent SQLite state. The executable
command SHALL be `nix build .#checks.x86_64-linux.authelia --print-build-logs`.

#### Scenario: Service integration check runs
- **WHEN** the Authelia flake check is executed
- **THEN** it boots a MicroVM and proves readiness, persistence, external-proxy boundary behavior, and secret-safe runtime input handling
