# gitea-declarative-identities Specification

## Purpose
Provides reproducible, idempotent provisioning of non-administrator Gitea
users and organizations in an impermanent MicroVM deployment.

## Requirements

### Requirement: Non-admin users are declaratively configurable

The system SHALL accept a declarative collection of non-admin users with a
stable username, email address, and runtime password-file path. User
definitions MAY include non-secret profile attributes supported by the
service. A declarative user SHALL be created without administrator privileges.

#### Scenario: User declaration is enabled

- **WHEN** a valid non-admin user declaration is present and Gitea is
  available
- **THEN** the user exists with the declared username and email, can
  authenticate with the runtime password, and does not have administrator
  privileges

#### Scenario: User declaration is invalid

- **WHEN** a declaration has a duplicate username, missing required field, or
  invalid password-file configuration
- **THEN** configuration evaluation fails with an actionable assertion rather
  than partially provisioning identities

#### Scenario: Existing administrator has a declarative username

- **WHEN** a declarative non-admin username refers to an existing administrator
- **THEN** reconciliation does not silently demote the account and reports the
  conflict without claiming successful non-admin enforcement

### Requirement: Organizations are declaratively configurable

The system SHALL accept a declarative collection of organizations with a
stable name, an owner reference to a declared user, and optional description
and visibility attributes. An organization SHALL be created only after its
owner user exists, and organization provisioning SHALL NOT grant administrator
privileges to the owner.

#### Scenario: Organization declaration is enabled

- **WHEN** a valid organization declaration references an existing or
  declaratively provisioned non-admin user
- **THEN** the organization exists with the declared owner and metadata, and
  the owner can access it through Gitea

#### Scenario: Organization references an unknown owner

- **WHEN** an organization references a username that is not declared or
  available in Gitea
- **THEN** evaluation or reconciliation fails clearly and does not create an
  organization with an unintended owner

#### Scenario: Organization visibility is declared

- **WHEN** an organization specifies a supported visibility value
- **THEN** the resulting organization exposes that visibility through Gitea
  and subsequent reconciliation preserves it

### Requirement: Identity reconciliation is idempotent and non-destructive

The system SHALL reconcile declarations after Gitea is available and on
configuration activation. Reconciliation SHALL update supported declarative
attributes without creating duplicate users or organizations. Removing a
declaration SHALL NOT delete or transfer the corresponding existing record.

#### Scenario: Guest restarts after reconciliation

- **WHEN** the guest restarts with the same declarations
- **THEN** the same users and organizations remain available, no duplicates are
  created, and reconciliation completes successfully

#### Scenario: Supported metadata changes

- **WHEN** a declared user's email/profile or organization's metadata changes
- **THEN** a later reconciliation applies the supported change to the existing
  record without changing its stable identity

#### Scenario: Declaration is removed

- **WHEN** a previously provisioned user or organization is removed from the
  declarative configuration
- **THEN** the existing record remains intact and no destructive cleanup is
  attempted

### Requirement: Declarative user credentials are secret-safe and rotatable

The system SHALL read each declared user's password from its configured file at
runtime. It SHALL NOT embed password contents in evaluated configuration,
generated store paths, unit definitions, persistent metadata, or logs. When a
password-file value changes, reconciliation SHALL rotate that user's password
using the replacement value and SHALL persist only non-reversible rotation
metadata.

#### Scenario: User password uses a SOPS secret

- **WHEN** a user password file points to a decrypted `sops-nix` secret path
- **THEN** provisioning reads the secret at runtime while evaluation retains
  only the path reference

#### Scenario: User password file changes

- **WHEN** configuration activation observes a changed secret-file value for an
  existing declared user
- **THEN** the user's password is replaced during reconciliation, the new
  password authenticates, and the previous password is rejected

#### Scenario: User password rotation fails

- **WHEN** a replacement password is missing, unreadable, or rejected by Gitea
- **THEN** the previous password remains usable, the failure is visible, and no
  success metadata is recorded

### Requirement: Identity provisioning is tested in a MicroVM

The Gitea MicroVM integration test SHALL boot an impermanent guest and exercise
declarative user and organization provisioning against the running service. It
SHALL verify primary authentication, organization access, persistence, safe
non-destructive behavior, and changed-secret rotation.

#### Scenario: End-to-end declarative identities

- **WHEN** the MicroVM boots with declared users and an organization
- **THEN** the users authenticate as non-admins, the organization has the
  declared owner and visibility, and the same records remain after restart

#### Scenario: End-to-end identity rotation

- **WHEN** a declared user's runtime password file changes and configuration
  activation or reconciliation runs
- **THEN** the new password authenticates, the old password fails, and the user
  remains a non-admin member with organization access
