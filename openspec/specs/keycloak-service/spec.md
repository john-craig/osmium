# keycloak-service Specification

## Purpose

Provides an isolated native Keycloak identity provider with explicit networking,
persistence, readiness, and a runtime-safe administrator credential lifecycle.

## Requirements

### Requirement: Keycloak runs as a native Osmium service

The system SHALL provide a disabled-by-default `services.osmium.keycloak`
service that composes the native NixOS Keycloak service with a pinned package
and SHALL NOT use a mutable OCI image or runtime package download. The service
SHALL expose typed options for its public issuer URL, guest and host ports,
database, persistence, TLS inputs, and runtime credential files.

#### Scenario: Enabled service starts

- **WHEN** an operator enables Keycloak with a valid declaration and runtime
  inputs
- **THEN** the guest starts the native Keycloak service and publishes a healthy
  OpenID Connect discovery endpoint at the declared issuer URL

#### Scenario: Invalid service declaration is rejected

- **WHEN** the declaration has an invalid issuer URL, unsafe path, unavailable
  required runtime input, or colliding network mapping
- **THEN** evaluation or readiness fails with an actionable diagnostic and no
  unintentionally unauthenticated endpoint becomes ready

### Requirement: Keycloak state and networking are explicit

The system SHALL use a locally managed PostgreSQL database by default, SHALL
persist the complete supported Keycloak and database state across impermanent
guest recreation, and SHALL expose explicit guest and host HTTP or HTTPS
mappings. The externally advertised issuer SHALL remain stable across reboot.
When LLDAP federation or the LLDAP administration gateway is enabled, Keycloak
SHALL validate the declared LLDAP TLS and lifecycle dependency before serving the
dependent path; LLDAP's browser upstream SHALL remain loopback-only.

#### Scenario: Identity state survives guest recreation

- **WHEN** realms and users exist and the MicroVM guest root is recreated
- **THEN** Keycloak returns with the same managed database state, issuer, and
  resource identities

#### Scenario: Public issuer is reachable

- **WHEN** a client resolves the declared issuer through the test or deployment
  network
- **THEN** discovery metadata and authorization endpoints use the declared
  externally reachable scheme, host, port, and path

#### Scenario: LLDAP dependency is unavailable

- **WHEN** enabled LLDAP federation or gateway configuration cannot validate its
  directory or loopback upstream
- **THEN** Keycloak does not report the dependent integration ready or expose an
  unauthenticated LLDAP administration path

### Requirement: Administrator bootstrap and rotation are secret-safe

The system SHALL bootstrap exactly one declared administrator from a runtime
password file, persist only non-secret completion metadata, and SHALL rotate the
administrator password when the file content changes. Secret bytes and
reversible secret digests MUST NOT enter the Nix store, generated
configuration, process arguments, journal, readiness output, or
reverse-configuration artifacts. An invalid replacement MUST preserve the last
working credential and MUST NOT be marked complete.

#### Scenario: Fresh service bootstraps the administrator

- **WHEN** a fresh persistent state starts with a valid administrator password
  file
- **THEN** exactly one declared administrator can authenticate and completion
  state contains no password bytes

#### Scenario: Administrator password file changes

- **WHEN** the runtime administrator password file is replaced with a different
  valid value
- **THEN** reconciliation applies the replacement once, rejects the old
  password, accepts the new password, and records only secret-free rotation
  state

#### Scenario: Administrator replacement is invalid

- **WHEN** a changed password file is empty, unreadable, or rejected by
  Keycloak
- **THEN** readiness reports failure, the previous password remains usable, and
  the replacement is not recorded as applied

### Requirement: Operational key material is runtime-only

The system SHALL accept database credentials and HTTPS key or keystore material
through runtime files when those features are enabled. Changed valid files SHALL
cause the affected service to reload or restart and consume the replacement;
invalid replacements MUST fail closed without copying secret contents into
persistent reconciliation metadata.

#### Scenario: HTTPS key material changes

- **WHEN** the declared HTTPS key material is replaced with a valid key and
  certificate
- **THEN** Keycloak reloads or restarts and subsequently serves the declared
  issuer with the replacement certificate

#### Scenario: Operational secret is unavailable

- **WHEN** an enabled database or HTTPS mode lacks a required readable runtime
  secret file
- **THEN** Keycloak does not become ready and reports the missing input without
  exposing secret content

### Requirement: Keycloak lifecycle is exercised in a MicroVM

The implementation SHALL provide a flake check that boots the Keycloak MicroVM,
uses the running OpenID Connect and administrative endpoints, verifies
administrator bootstrap and changed-file rotation, recreates or reboots the
guest, and proves persistence. The executable command SHALL be `nix build
.#checks.x86_64-linux.keycloak --print-build-logs`.

#### Scenario: Keycloak integration check runs

- **WHEN** the Keycloak flake check is executed
- **THEN** it proves the live service is healthy, authenticated administration
  works, changed credentials rotate, and state survives the lifecycle transition
