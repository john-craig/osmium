# keycloak-lldap-federation Specification

## Purpose

Connects Keycloak to LLDAP over verified LDAP while retaining Keycloak-local
users and keeping directory bind credentials runtime-only and rotatable.

## Requirements

### Requirement: Keycloak federation uses LLDAP securely

The system SHALL provide typed per-realm LLDAP federation declarations for
directory reference, supported user/group mapping subset, TLS trust reference,
and a dedicated runtime bind-password file. It SHALL validate endpoint identity
and TLS before enabling the provider. Existing local users SHALL remain local,
and local/federated username collisions MUST fail closed.

#### Scenario: LLDAP user signs in through Keycloak

- **WHEN** a declared LLDAP user completes a Keycloak authorization flow
- **THEN** Keycloak authenticates the user through verified LDAP and returns supported declared group claims while a local user still authenticates locally

### Requirement: Federation bind credentials have isolated lifecycle

The system SHALL provision one restricted managed LLDAP bind identity per
Keycloak federation declaration. Its password SHALL rotate from its dedicated
runtime file, and its value MUST NOT appear in logs, declarations, ledgers, or
reverse configuration.

#### Scenario: Bind password rotates

- **WHEN** the federation bind-password file changes to a valid value
- **THEN** live federation continues through the replacement and the old bind credential is rejected

### Requirement: Federation is exercised in a MicroVM

The implementation SHALL provide a booting `lldap-keycloak-federation` flake
check. The executable command SHALL be `nix build
.#checks.x86_64-linux.lldap-keycloak-federation --print-build-logs`.

#### Scenario: Federation integration check runs

- **WHEN** the federation check is executed
- **THEN** it boots LLDAP and Keycloak MicroVMs and verifies federated login, local-user coexistence, TLS denial, and bind-secret rotation
