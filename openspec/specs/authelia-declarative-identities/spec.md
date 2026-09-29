# authelia-declarative-identities Specification

## Purpose

Provides secret-safe declarative local identities and supported one-time TOTP
bootstrap for the Authelia YAML file authentication backend.

## Requirements

### Requirement: Local identities are declarative and runtime-secret backed
The system SHALL support stable declarative local users with username, enabled
state, display name, email, groups, and password-file references. It SHALL render
the supported YAML file-backend records at runtime and hash supplied passwords
using Authelia's supported mechanism. It SHALL reject duplicate usernames or
emails, invalid user metadata, unsafe files, and undeclared group references
before mutation.

#### Scenario: Declared user authenticates
- **WHEN** a valid user declaration and readable password file are applied
- **THEN** the user can authenticate with the declared username and password and receives the declared identity metadata and groups

#### Scenario: Invalid identity declaration is rejected
- **WHEN** users have a duplicate identity, invalid metadata, invalid group reference, or unreadable password file
- **THEN** evaluation or reconciliation fails without adopting or mutating an unrelated user

### Requirement: Password bootstrap and rotation are secret-safe
The system SHALL create each managed user from its password file exactly once and
shall rotate that user's password when the file content changes. The reconciler
SHALL persist only stable identity metadata and a salted non-reversible change
fingerprint. It MUST validate the replacement through live authentication before
recording it; an empty, unreadable, or rejected replacement MUST preserve the
last working password and completion state.

#### Scenario: Password file changes
- **WHEN** a user's runtime password file changes to a valid value
- **THEN** the old password is rejected, the replacement authenticates, and no plaintext password or reversible derivative is persisted

#### Scenario: Password replacement fails
- **WHEN** a changed password file is empty, unreadable, or cannot be applied
- **THEN** reconciliation fails, the old password remains usable, and the changed value is not marked applied

### Requirement: TOTP bootstrap is explicit and one-time
The system SHALL support an optional per-user runtime-only TOTP bootstrap input
using supported Authelia storage tooling. It SHALL create or import the factor
only when no managed factor exists, persist a secret-free completion marker, and
write any generated enrollment material only to a declared protected output path.
It MUST NOT repeat enrollment, rotate an existing factor, or expose TOTP secrets,
URIs, QR data, recovery material, or reversible derivatives in declarations,
logs, ledgers, capture output, or the Nix store.

#### Scenario: Fresh user receives TOTP bootstrap
- **WHEN** a user with a valid TOTP bootstrap declaration has no enrolled factor
- **THEN** Authelia creates or imports one factor once and records only that bootstrap completed

#### Scenario: Existing factor is preserved
- **WHEN** a user already has a managed or user-enrolled TOTP factor and the service is reconciled or rebooted
- **THEN** the factor is not replaced and no enrollment secret is regenerated

### Requirement: Declarative identities are verified in a MicroVM
The implementation SHALL provide a booting `authelia-identities` flake check that
uses the running authentication portal and storage tooling to verify user and
group provisioning, password rotation, TOTP bootstrap, second-factor
authentication, persistence, and secret exclusion. The executable command SHALL
be `nix build .#checks.x86_64-linux.authelia-identities --print-build-logs`.

#### Scenario: Identity integration check runs
- **WHEN** the identity flake check is executed
- **THEN** it boots a MicroVM and verifies live one-factor and two-factor behavior rather than only evaluating module options
