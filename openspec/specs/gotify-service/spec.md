# gotify-service Specification

## Purpose

Provides an isolated, native Gotify notification server with explicit state,
networking, and administrator credential lifecycle in an Osmium MicroVM.

## Requirements

### Requirement: Gotify runs as a native Osmium service

The system SHALL provide an enabled `services.osmium.gotify` service that uses
the native NixOS Gotify service and SHALL not use a mutable OCI image or a
runtime package download.

#### Scenario: Enabled service starts

- **WHEN** an operator enables the Gotify service
- **THEN** the guest enables the native Gotify systemd service and exposes its
  configured HTTP endpoint

#### Scenario: Disabled service has no guest integration

- **WHEN** the Gotify service is disabled
- **THEN** no Gotify persistence declaration, bootstrap unit, reconciler, or
  MicroVM guest integration is generated

### Requirement: Gotify state and networking are explicit

The system SHALL persist the configured Gotify state directory and SHALL expose
an explicit guest HTTP port and host forwarding port. It MUST reject an enabled
configuration with an invalid or colliding host port mapping.

#### Scenario: State survives guest recreation

- **WHEN** the service stores Gotify data and the MicroVM guest root is
  recreated
- **THEN** the service starts with the same persisted Gotify state

#### Scenario: HTTP port is configured

- **WHEN** an enabled service declares guest and host HTTP ports
- **THEN** Gotify listens on the guest port and the MicroVM forwards the host
  port to it

### Requirement: Administrator bootstrap is one-time and secret-safe

The system SHALL support an optional administrator bootstrap declaration with a
username and runtime password file. It SHALL consume the password only after
Gotify is available, persist non-secret completion metadata, and SHALL NOT
recreate, rotate, print, log, or store the password after successful bootstrap.

#### Scenario: Fresh service bootstraps administrator

- **WHEN** a new persisted Gotify state directory starts with a valid bootstrap
  password file
- **THEN** exactly one administrator account is available and the completion
  state proves bootstrap succeeded without containing the password

#### Scenario: Administrator bootstrap repeats

- **WHEN** the service restarts with unchanged persisted completion state
- **THEN** it leaves the administrator account and credential unchanged

#### Scenario: Bootstrap input is unavailable

- **WHEN** bootstrap is required but its password file is empty or unreadable
- **THEN** startup reports an actionable failure without creating a partial
  administrator account or recording successful completion

### Requirement: Gotify lifecycle is exercised in a MicroVM

The implementation SHALL provide a flake check that boots the Gotify MicroVM,
exercises its HTTP API and administrator bootstrap, recreates or restarts the
guest, and verifies persistence. The executable check command SHALL be `nix
build .#checks.x86_64-linux.gotify --print-build-logs`.

#### Scenario: Service integration check runs

- **WHEN** the Gotify flake check is executed
- **THEN** it proves a running Gotify server accepts authenticated API requests
  before and after the tested lifecycle transition
