## Purpose

Provides an opt-in, one-time administrator bootstrap for the native Gitea
service while keeping the administrator password out of evaluated Nix
configuration and the Nix store.

## ADDED Requirements

### Requirement: Administrator bootstrap is configurable

The system SHALL expose an opt-in Gitea administrator bootstrap with a
non-secret username, an email address, and a password file path. The password
file path SHALL support paths produced by `sops-nix` secret declarations.

#### Scenario: Bootstrap is enabled

- **WHEN** administrator bootstrap is enabled with a username and password
  file
- **THEN** the guest configuration schedules a one-time administrator creation
  after Gitea is available

#### Scenario: Bootstrap is disabled

- **WHEN** administrator bootstrap is disabled
- **THEN** no administrator bootstrap unit or marker is generated

### Requirement: Bootstrap is one-time and persistent

The system SHALL record successful bootstrap completion in the persisted Gitea
state directory and SHALL not recreate or modify the configured administrator
on subsequent service starts.

#### Scenario: Initial bootstrap succeeds

- **WHEN** Gitea is running and the configured administrator does not exist
- **THEN** the administrator is created with administrator privileges and the
  completion marker is written only after successful creation

#### Scenario: Guest restarts after bootstrap

- **WHEN** the guest restarts after successful bootstrap
- **THEN** the administrator remains available and the bootstrap does not run a
  second time

#### Scenario: Bootstrap fails

- **WHEN** administrator creation fails
- **THEN** the bootstrap unit fails and no completion marker is written

### Requirement: Bootstrap credentials are secret-safe

The system SHALL consume the administrator password at runtime from the
configured file path and SHALL NOT embed the password contents in evaluated Nix
configuration, generated store paths, unit definitions, or logs.

#### Scenario: SOPS password is configured

- **WHEN** `passwordFile` references a `sops-nix` secret path
- **THEN** the bootstrap reads the decrypted runtime secret and the evaluated
  configuration contains only the path reference

### Requirement: Administrator behavior is tested in a MicroVM

The Gitea MicroVM test SHALL boot a clean guest, execute the bootstrap, verify
administrator authentication, restart the guest, and verify the account still
authenticates without a second bootstrap.

#### Scenario: End-to-end administrator bootstrap

- **WHEN** the Gitea MicroVM test starts with a configured password fixture
- **THEN** the bootstrap-created administrator can authenticate before and
  after guest restart and the persistent completion marker exists
