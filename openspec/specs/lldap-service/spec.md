# lldap-service Specification

## Purpose

Provides a persistent native LLDAP directory with secure bootstrap, explicit
LDAP and administration-UI boundaries, and Keycloak-protected browser access.

## Requirements

### Requirement: LLDAP runs as a native Osmium service

The system SHALL provide a disabled-by-default `services.osmium.lldap` service
that composes the native NixOS LLDAP module and pinned package. It SHALL expose
typed declarations for LDAP base DN, guest and host LDAP/LDAPS ports, loopback
administration listener, public HTTPS administration URL, state path, and
runtime secret files. It SHALL NOT use a mutable container image or runtime
package download.

#### Scenario: Valid LLDAP service starts

- **WHEN** an operator enables LLDAP with valid naming, networking, state, and runtime inputs
- **THEN** a MicroVM starts the directory and accepts authenticated LDAP requests

#### Scenario: Invalid LLDAP declaration is rejected

- **WHEN** LDAP naming is malformed, a required runtime input is unsafe or unavailable, or a network mapping collides
- **THEN** evaluation or readiness fails with an actionable diagnostic before an unauthenticated service is exposed

### Requirement: State and bootstrap credentials are safe

The system SHALL persist LLDAP database and supported service state across
impermanent guest recreation. It SHALL bootstrap exactly one administrator from
a protected runtime password file and consume required JWT and password-key
material only from protected runtime files. Changed valid files SHALL be
consumed by a validated restart or reconciliation; invalid replacements MUST
preserve the last working state. Secret bytes and reversible secret derivatives
MUST NOT enter the Nix store, generated configuration, process arguments,
journal, readiness output, ledgers, or reverse-configuration artifacts.

#### Scenario: Bootstrap input changes after initialization

- **WHEN** a runtime administrator password file changes after the initial database bootstrap
- **THEN** the declared rotation policy changes the administrator credential exactly once without exposing either value

#### Scenario: Cryptographic input is invalid

- **WHEN** a JWT secret or password-key file is empty, unreadable, or invalid
- **THEN** LLDAP does not become ready with the replacement and the prior usable state remains recoverable

### Requirement: LDAP and browser administration boundaries are explicit

The service SHALL expose LDAP and LDAPS only through declared guest and host
ports, and SHALL bind its HTTP administration listener to loopback. Because
LLDAP has neither HTTPS nor native OpenID Connect client support, the module
SHALL require the bounded Keycloak gateway for browser administration: a
loopback-only upstream, separate browser and machine endpoints, runtime-only
client and cookie secrets, and stripped identity headers. LDAP and GraphQL
machine authentication MUST NOT use the browser gateway.

#### Scenario: Browser administration passes through Keycloak

- **WHEN** an authorized operator accesses the declared HTTPS administration URL
- **THEN** the gateway completes Keycloak login before proxying to the loopback LLDAP UI without forwarding identity headers

#### Scenario: Direct or bypass access is denied

- **WHEN** a peer attempts direct LLDAP HTTP access or reaches the browser endpoint without a valid Keycloak session
- **THEN** no administration UI is served

### Requirement: FreeIPA platform features are not represented

The service SHALL support only LLDAP's documented LDAP user and group
capabilities. It SHALL NOT declare or imply Kerberos, DNS, host enrollment,
certificate issuance, HBAC/sudo policy, replicas, LDAP schema management, or
general LDAP write compatibility.

#### Scenario: Unsupported identity-platform feature is requested

- **WHEN** an operator declares a FreeIPA-specific or unsupported LDAP-platform feature
- **THEN** evaluation rejects the declaration rather than silently enabling or emulating it

### Requirement: LLDAP lifecycle is exercised in a MicroVM

The implementation SHALL provide a booting `lldap` flake check. The executable
command SHALL be `nix build .#checks.x86_64-linux.lldap --print-build-logs`.

#### Scenario: LLDAP integration check runs

- **WHEN** the LLDAP flake check is executed
- **THEN** it boots a MicroVM and verifies live LDAP behavior, bootstrap, runtime-secret handling, browser-gateway login/denial/bypass boundaries, and persistent guest recreation
