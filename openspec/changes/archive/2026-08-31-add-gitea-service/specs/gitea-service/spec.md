## Purpose

Provides a reproducible, isolated Gitea instance whose application state is
explicitly declared and survives recreation of the guest root filesystem.

## ADDED Requirements

### Requirement: Gitea runs as a native service instance

The system SHALL provide an enabled Gitea service instance using the native
NixOS Gitea service rather than a mutable OCI image or runtime installer.

#### Scenario: Enabled Gitea instance

- **WHEN** a Gitea instance is enabled
- **THEN** the resulting guest configuration enables `services.gitea` and
  starts Gitea through its systemd service

#### Scenario: Disabled Gitea instance

- **WHEN** the Gitea instance is disabled
- **THEN** no Gitea systemd service, persistence declaration, or guest VM is
  generated for that instance

### Requirement: Gitea state is explicitly persistent

The system SHALL persist the Gitea state directory and all configured data
locations required to retain repositories and application state across guest
root recreation.

#### Scenario: State survives reboot

- **WHEN** a repository and Gitea state are written and the guest reboots
- **THEN** the repository and state are available after Gitea starts again

#### Scenario: Undeclared root state is ephemeral

- **WHEN** a file is written outside the declared persistent locations and the
  guest root is recreated
- **THEN** that file is absent after reboot

### Requirement: Gitea networking is deterministic

The system SHALL expose configurable HTTP and SSH guest ports and SHALL reject
an enabled instance whose host HTTP and SSH mappings collide.

#### Scenario: HTTP and SSH ports are configured

- **WHEN** an instance specifies HTTP and SSH host ports
- **THEN** the guest listens on the declared guest ports and the host forwards
  traffic to the matching guest ports

#### Scenario: HTTP and SSH host port collision is rejected

- **WHEN** an enabled instance requests the same host port for HTTP and SSH
- **THEN** evaluation fails with an assertion identifying the conflicting ports

### Requirement: Gitea configuration is reproducible and secret-safe

The system SHALL expose declarative Gitea settings and SHALL support the
database password through a file path without placing the secret contents in
the Nix store.

#### Scenario: Declarative settings

- **WHEN** an operator supplies Gitea settings
- **THEN** the generated guest configuration contains those settings without a
  runtime configuration-generation step

#### Scenario: Database password file configuration

- **WHEN** a database password is configured by file path
- **THEN** the guest references that path and the secret value is not embedded
  in evaluated Nix configuration or store content

### Requirement: Gitea behavior is tested in a MicroVM

The system SHALL provide an automated MicroVM test that verifies service
startup, HTTP reachability, repository creation, and persistence across reboot.

#### Scenario: End-to-end persistence test

- **WHEN** the Gitea MicroVM test boots a clean guest
- **THEN** it reaches the HTTP endpoint, creates or accesses a repository,
  reboots the guest, and verifies the repository remains available
