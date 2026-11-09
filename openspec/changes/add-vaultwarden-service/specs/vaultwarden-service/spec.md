## Purpose

Provides an isolated native Vaultwarden password-vault service with explicit
networking, persistence, readiness, runtime credentials, and a documented
exception to Osmium's shared Keycloak SSO gateway policy.

## ADDED Requirements

### Requirement: Vaultwarden runs as a native Osmium service

The system SHALL provide a disabled-by-default `services.osmium.vaultwarden`
service using the pinned Nixpkgs Vaultwarden package. It SHALL expose typed
options for the guest bind address, guest and host ports, public URL, state
directory, database, persistence, runtime administrator inputs, and deployment
credentials. It MUST reject invalid paths, unsafe public URLs, and colliding
network mappings before activation.

#### Scenario: Valid service starts

- **WHEN** an operator enables Vaultwarden with valid runtime inputs and a
  declared public URL
- **THEN** the MicroVM starts the native service, exposes its health and client
  endpoints on the declared listener, and reports readiness only after the
  persistent state and required runtime inputs are available

#### Scenario: Invalid service declaration is rejected

- **WHEN** a declaration contains an invalid URL, unsafe path, unavailable
  required input, or colliding guest or host port
- **THEN** evaluation or readiness fails with an actionable diagnostic and does
  not expose an unintentionally unauthenticated service

### Requirement: Vaultwarden state and runtime credentials have separate lifecycles

The service SHALL persist supported Vaultwarden database and attachment state
across impermanent guest recreation while keeping runtime credential mounts,
administrator tokens, and provisioning input files non-persistent and
read-only. Secret values MUST NOT enter the Nix store, generated units,
persistent ledgers, logs, readiness output, or reverse-configuration output.

#### Scenario: Vault state survives guest recreation

- **WHEN** users, organizations, memberships, and organization ciphers exist and
  the impermanent guest root is recreated
- **THEN** Vaultwarden returns with the same supported state and identities

#### Scenario: Runtime secret mount is unavailable

- **WHEN** an enabled bootstrap or provisioning input is missing, empty,
  unreadable, or malformed
- **THEN** the affected operation fails closed without copying its contents into
  persistent state or exposing a usable unauthenticated administrative path

### Requirement: Vaultwarden is explicitly exempt from shared Keycloak SSO

Vaultwarden SHALL retain its native Bitwarden-compatible account, master-key,
and encrypted-sync authentication protocol and SHALL NOT be placed behind the
shared Keycloak browser gateway. The exemption documentation and configuration
MUST identify that a gateway login cannot replace native client authentication
or vault-key derivation. Machine and browser clients SHALL continue to use
Vaultwarden-native authentication without OIDC redirects.

#### Scenario: Native client authentication remains available

- **WHEN** a Bitwarden-compatible client synchronizes using a provisioned
  Vaultwarden account and its native credentials
- **THEN** authentication and encrypted vault synchronization succeed without a
  Keycloak redirect

#### Scenario: SSO boundary is tested

- **WHEN** a client requests the Vaultwarden web or API endpoint without native
  credentials or attempts an OIDC gateway route
- **THEN** Vaultwarden applies its native authentication behavior and no
  Keycloak SSO session is minted or accepted as a substitute

### Requirement: Vaultwarden lifecycle is exercised in a MicroVM

The implementation SHALL provide a booting MicroVM check that verifies
readiness, native client authentication, state persistence, runtime-only
credential handling, and the explicit no-Keycloak-SSO boundary. The executable
command SHALL be `nix build .#checks.x86_64-linux.vaultwarden
--print-build-logs`.

#### Scenario: Service integration check runs

- **WHEN** the Vaultwarden service check is executed
- **THEN** it exercises the running Vaultwarden API and client boundary rather
  than only evaluating options or building a system closure
