# authelia-lldap-authentication Specification

## Purpose

Lets Authelia use LLDAP over verified LDAP as its sole first-factor backend
while retaining the existing file backend for explicit rollback.

## Requirements

### Requirement: Authelia can select LLDAP as its LDAP backend

The system SHALL provide typed LLDAP backend declarations for directory
reference, endpoint, base DN, supported user/group search subset, TLS trust
reference, and a dedicated runtime bind-password file. In LLDAP mode, Authelia
SHALL use LDAP as its sole first-factor backend and MUST reject insecure LDAP,
invalid filters, unavailable directories, unsafe paths, or invalid trust.

#### Scenario: LLDAP user authenticates to Authelia

- **WHEN** a declared LLDAP user signs in through Authelia with a valid verified-LDAP configuration
- **THEN** Authelia authenticates the user and applies declared group-based access policy

### Requirement: File-backend transition is explicit and reversible

Enabling LLDAP SHALL retain but disable Authelia's file backend. Disabling the
integration SHALL explicitly restore that retained backend. Neither transition
SHALL copy, modify, migrate, or delete credentials in LLDAP or the file backend.

#### Scenario: LLDAP mode excludes file-only users

- **WHEN** LLDAP mode is enabled and a file-only user attempts login
- **THEN** Authelia denies that login until the operator explicitly restores the file backend

### Requirement: Authelia LLDAP integration is exercised in a MicroVM

The implementation SHALL provide a booting `lldap-authelia-ldap-authentication`
flake check. The executable command SHALL be `nix build
.#checks.x86_64-linux.lldap-authelia-ldap-authentication --print-build-logs`.

#### Scenario: Authelia LDAP integration check runs

- **WHEN** the check is executed
- **THEN** it boots LLDAP and Authelia MicroVMs and verifies LDAP login, group authorization, bind-secret rotation, invalid-trust denial, file-only login denial, and explicit rollback
