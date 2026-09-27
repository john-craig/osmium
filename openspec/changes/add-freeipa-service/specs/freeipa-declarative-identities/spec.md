## Purpose

Provides declarative, secret-safe FreeIPA users and groups for shared LDAP and
Kerberos authentication while preserving explicit ownership and lifecycle state.

## ADDED Requirements

### Requirement: FreeIPA users and groups are declarative
The system SHALL support stable declarative FreeIPA users with username, enabled
state, display and identity metadata, email, group membership, and runtime
password-file references, plus stable declarative groups. It SHALL reject
duplicate UID, username, email, group, or UNIX identity values, invalid metadata,
unsafe input paths, and unresolved group references before mutation.

#### Scenario: Declared directory user authenticates
- **WHEN** a valid user and group declaration is reconciled with its password file
- **THEN** the user exists once in FreeIPA, has the declared group memberships, authenticates over LDAPS, and obtains a Kerberos ticket

#### Scenario: Invalid directory reference is rejected
- **WHEN** a declaration has duplicate identity data or references an undeclared group
- **THEN** evaluation fails before FreeIPA adds or modifies a directory record

### Requirement: Directory password lifecycle is secret-safe
The system SHALL initialize managed user passwords from runtime files and SHALL
rotate a password when the source content changes. It SHALL persist only stable
directory identifiers and salted non-reversible change fingerprints. A valid
replacement SHALL be validated through live LDAP and Kerberos authentication
before commit; an empty, unreadable, or rejected replacement MUST preserve the
prior working password and ledger state.

#### Scenario: User password changes
- **WHEN** a managed user's password file receives a different valid value
- **THEN** the old credential is rejected by LDAP and Kerberos, the replacement authenticates, and no password value or reversible derivative is persisted

#### Scenario: User password replacement fails
- **WHEN** a changed user password file is invalid or cannot be applied
- **THEN** the service reports reconciliation failure and the prior user credential remains usable

### Requirement: Managed directory lifecycle is safe and explicit
The system SHALL maintain a protected, versioned non-secret ownership ledger for
managed users and groups. Removal or update SHALL affect only records whose
stable identity and ownership are proven. Unmanaged or ambiguous records MUST NOT
be adopted, deleted, disabled, or have memberships changed. Default removal
behavior SHALL retain a managed record unless an explicit supported removal policy
authorizes a narrower action.

#### Scenario: Managed group membership changes
- **WHEN** a declared managed user's group membership changes
- **THEN** only the proven managed membership is reconciled and unrelated users or unmanaged groups are unchanged

#### Scenario: Ownership is ambiguous
- **WHEN** a declared identity collides with an unmanaged FreeIPA record without compatible ownership evidence
- **THEN** reconciliation fails closed without changing that record

### Requirement: Declarative directory identities are verified in a MicroVM
The implementation SHALL provide a booting `freeipa-identities` flake check that
uses running FreeIPA LDAP, Kerberos, and administrative interfaces to verify user
and group provisioning, password rotation, safe lifecycle behavior, persistence,
and secret exclusion. The executable command SHALL be `nix build
.#checks.x86_64-linux.freeipa-identities --print-build-logs`.

#### Scenario: Directory identity check runs
- **WHEN** the FreeIPA identity check is executed
- **THEN** it boots a MicroVM and proves live LDAP/Kerberos authentication and rotation rather than only evaluating declarations
