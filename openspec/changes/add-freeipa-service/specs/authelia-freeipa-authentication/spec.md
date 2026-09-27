## Purpose

Provides Authelia first-factor authentication through the managed FreeIPA LDAP
directory with a deliberate, reversible transition from its YAML file backend.

## ADDED Requirements

### Requirement: Authelia can use FreeIPA as its LDAP first-factor backend
The system SHALL allow an enabled Authelia service to reference a declared enabled
FreeIPA service through typed LDAP settings including directory endpoint, base DN,
user/group search subset, CA trust reference, and a dedicated runtime bind
credential. It SHALL verify LDAP TLS identity and trust, reject insecure LDAP,
unsafe bind input paths, invalid filters, or unavailable FreeIPA dependencies,
and SHALL keep bind credential values out of evaluated configuration, logs,
ledgers, observations, and candidates.

#### Scenario: FreeIPA user signs in through Authelia
- **WHEN** an eligible FreeIPA user supplies valid directory credentials to Authelia LDAP mode
- **THEN** Authelia authenticates the user over verified LDAPS and applies access-control rules to the represented FreeIPA group membership

#### Scenario: LDAP trust or bind credential fails
- **WHEN** the FreeIPA CA trust, endpoint identity, or bind credential is invalid or unavailable
- **THEN** Authelia does not become ready for LDAP authentication and does not fall back to insecure LDAP or disclose the failed secret

### Requirement: File-backend transition is explicit and reversible
Enabling Authelia FreeIPA LDAP authentication SHALL select LDAP as Authelia's sole
first-factor backend. Existing YAML file-backend records SHALL remain intact in
persistent state for rollback but SHALL NOT authenticate while LDAP mode is
enabled. Disabling the integration SHALL require explicit operator action and
restore only the retained YAML backend; it SHALL NOT migrate, delete, or modify
directory or file-backend user credentials automatically.

#### Scenario: LDAP mode replaces YAML authentication
- **WHEN** a running Authelia service with retained YAML records is changed to enabled FreeIPA LDAP mode
- **THEN** eligible FreeIPA users can authenticate and a YAML-only user cannot authenticate until the operator explicitly disables LDAP mode

#### Scenario: LDAP mode is disabled
- **WHEN** an operator explicitly disables the FreeIPA LDAP integration after a valid prior YAML backend exists
- **THEN** Authelia returns to the retained YAML backend without changing FreeIPA users or passwords

### Requirement: Authelia LDAP integration is verified in a joint MicroVM check
The implementation SHALL provide a booting `freeipa-authelia-ldap-authentication`
flake check that starts FreeIPA and Authelia, provisions a directory user and bind
account, verifies live LDAP login and group authorization, demonstrates YAML
backend denial in LDAP mode, rotates the bind credential, and verifies explicit
rollback to the retained YAML backend. The executable command SHALL be `nix build
.#checks.x86_64-linux.freeipa-authelia-ldap-authentication --print-build-logs`.

#### Scenario: Authelia LDAP integration check runs
- **WHEN** the Authelia LDAP integration check is executed
- **THEN** it boots the involved MicroVMs and exercises the actual authentication transition, authorization, rotation, and rollback behavior
