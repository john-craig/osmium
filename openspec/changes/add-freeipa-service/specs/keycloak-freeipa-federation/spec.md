## Purpose

Provides Keycloak login federation from the managed FreeIPA LDAP directory while
preserving Keycloak-local accounts and their existing authentication behavior.

## ADDED Requirements

### Requirement: Keycloak can federate FreeIPA users over verified LDAPS
The system SHALL allow a Keycloak realm to reference a declared enabled FreeIPA
service through typed LDAP federation settings including a stable provider name,
directory endpoint, base DN, user and group mapping subset, CA trust reference,
and dedicated runtime bind credential. It SHALL verify the endpoint identity and
CA trust, reject insecure LDAP, ambiguous mappings, absent FreeIPA references,
or unsafe bind input paths, and SHALL NOT expose bind credentials in evaluated
configuration, logs, ledgers, observations, or candidates.

#### Scenario: Federated FreeIPA user signs in to Keycloak
- **WHEN** a declared FreeIPA user with valid directory credentials signs in to a realm with enabled federation
- **THEN** Keycloak authenticates the user through verified LDAPS and exposes the represented FreeIPA group membership in configured claims

#### Scenario: Directory trust or bind input is invalid
- **WHEN** the FreeIPA CA trust, endpoint identity, or bind credential is missing, changed to an invalid value, or rejected
- **THEN** Keycloak does not authenticate the federated user and does not weaken TLS verification or leak the failed secret

### Requirement: Federation preserves local Keycloak users
Enabled FreeIPA federation SHALL coexist with existing Keycloak-local users,
their managed passwords, roles, groups, clients, and OIDC behavior. Reconciliation
MUST NOT convert, overwrite, delete, or adopt a local Keycloak user merely because
a FreeIPA user has the same identity; ambiguous duplicate identities MUST fail
closed with an actionable diagnostic.

#### Scenario: Local and federated accounts coexist
- **WHEN** a realm contains a non-conflicting managed local user and a FreeIPA user
- **THEN** both accounts continue to authenticate through their respective backends

#### Scenario: Local and federated identities collide
- **WHEN** a FreeIPA user conflicts with an existing local Keycloak username or other unique identity
- **THEN** federation reconciliation reports the conflict without mutating either account

### Requirement: Federation is verified in a joint MicroVM check
The implementation SHALL provide a booting `freeipa-keycloak-federation` flake
check that starts FreeIPA and Keycloak, provisions a directory user and bind
account, verifies live LDAPS federation and group claims, proves local-user
coexistence, rotates the bind credential, and rejects an invalid trust or
credential replacement. The executable command SHALL be `nix build
.#checks.x86_64-linux.freeipa-keycloak-federation --print-build-logs`.

#### Scenario: Keycloak federation check runs
- **WHEN** the Keycloak federation flake check is executed
- **THEN** it boots the involved MicroVMs and exercises real directory-backed and local OIDC login behavior
