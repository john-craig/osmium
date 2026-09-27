## Purpose

Provides a native, impermanent-friendly Home Assistant service with explicit
networking, persistence, runtime credentials, and a deferred hardware boundary.

## ADDED Requirements

### Requirement: Home Assistant runs as a native Osmium service

The system SHALL provide a disabled-by-default `services.osmium.homeAssistant`
service that composes the pinned Nixpkgs Home Assistant package. It SHALL expose
typed options for the instance name, public URL, guest bind address, guest and
host ports, state/configuration paths, persistence, runtime credentials, and
supported configuration inputs. Invalid URLs, paths, listener settings, and port
mappings MUST fail evaluation with actionable diagnostics.

#### Scenario: Valid service starts

- **WHEN** an operator enables the service with valid state, networking, and
  runtime-input declarations
- **THEN** the MicroVM runs Home Assistant, publishes the declared healthy
  endpoint, and reports ready only after required configuration and state exist

#### Scenario: Invalid service declaration is rejected

- **WHEN** a declaration has an invalid public URL, unsafe path, unsupported
  listener, or colliding guest or host port
- **THEN** evaluation fails before an unintended service endpoint becomes ready

### Requirement: State persists separately from runtime secrets

The service SHALL persist supported Home Assistant state, history, database,
configuration, dashboards, and generated declarative metadata across
impermanent guest recreation. Runtime credential files, Keycloak client/cookie
secrets, recovery passwords, and machine tokens MUST remain non-persistent and
read-only. Secret values MUST NOT enter the Nix store, generated configuration,
unit arguments, logs, ledgers, readiness output, or reverse-configuration
output.

#### Scenario: Service state survives guest recreation

- **WHEN** Home Assistant has completed setup and the impermanent guest root is
  recreated
- **THEN** declared configuration and supported persisted state return with the
  same identity and without repeating unchanged bootstrap

#### Scenario: Required runtime input is unavailable

- **WHEN** an enabled recovery, machine, or gateway credential file is missing,
  empty, unreadable, or malformed
- **THEN** the dependent path fails closed without exposing an unauthenticated
  browser or machine endpoint

### Requirement: Privileged bootstrap is one-time and rotatable

The service SHALL support a one-time native Home Assistant owner bootstrap from
a protected runtime credential file and SHALL maintain a separate restricted
gateway user for browser SSO. It SHALL persist only secret-free completion and
rotation metadata. Changed owner or gateway credential files SHALL trigger
runtime validation and rotation when supported; invalid replacements MUST
preserve the last usable credential and not be marked complete.

#### Scenario: Initial owner is bootstrapped

- **WHEN** a fresh service starts with a valid owner credential file
- **THEN** exactly one declared native recovery owner is available and no
  password value appears in persistent completion state

#### Scenario: Owner credential changes

- **WHEN** the protected owner credential file receives a different valid value
- **THEN** native recovery authentication accepts the replacement, rejects the
  previous value, and retains only non-reversible rotation metadata

#### Scenario: Owner credential replacement fails

- **WHEN** a replacement owner credential is invalid or cannot be applied
- **THEN** the prior recovery credential remains usable and the replacement is
  not recorded as applied

### Requirement: Hardware passthrough is explicitly deferred

The service MUST NOT expose host USB, serial, Bluetooth, Zigbee, Z-Wave, GPIO,
or other physical-device passthrough in this change. Declarations requiring a
host device or hardware-dependent integration SHALL fail evaluation or be
reported unsupported rather than broadening MicroVM access implicitly.

#### Scenario: Hardware-dependent declaration is requested

- **WHEN** an operator declares a USB, serial, Bluetooth, Zigbee, Z-Wave, GPIO,
  or other host-device input
- **THEN** the service rejects or classifies the declaration as unsupported and
  does not attach the device to the MicroVM

### Requirement: Home Assistant lifecycle is exercised in a MicroVM

The implementation SHALL provide a booting MicroVM check for native service
startup, owner bootstrap, credential rotation, persistence, declarative
configuration loading, and the hardware-passthrough boundary. The executable
command SHALL be `nix build .#checks.x86_64-linux.home-assistant
--print-build-logs`.

#### Scenario: Service integration check runs

- **WHEN** the Home Assistant service check executes
- **THEN** it boots and exercises the running service rather than only
  evaluating NixOS options or building a closure
