## Purpose

Provides a safe, persistent expiration policy and replacement workflow for the
administrator credential created by the Mythoclast Gitea service.

## ADDED Requirements

### Requirement: Credential rotation is explicitly configurable

The system SHALL expose an opt-in administrator credential rotation policy
with a maximum credential age, a check interval, and a runtime file containing
the desired replacement credential. Rotation SHALL remain disabled unless the
policy is explicitly enabled.

#### Scenario: Rotation is disabled

- **WHEN** administrator credential rotation is disabled
- **THEN** the existing one-time bootstrap behavior remains unchanged and no
  rotation timer or rotation state is created

#### Scenario: Rotation is enabled

- **WHEN** rotation is enabled with a valid age, interval, and replacement
  credential file
- **THEN** the guest schedules periodic expiration checks after Gitea is
  available

### Requirement: Expiration and activation trigger controlled rotation

The system SHALL consider the administrator credential due for rotation when
the configured maximum age has elapsed since the last successful rotation or
initial bootstrap. It SHALL also attempt rotation during configuration
activation when the replacement file identifies a credential different from
the last successfully applied one. When either trigger occurs, it SHALL apply
the replacement credential and record successful rotation metadata only after
Gitea confirms the change.

#### Scenario: Activation supplies a changed credential

- **WHEN** configuration activation enables rotation or updates the
  replacement file and its credential identity differs from the persisted
  applied identity
- **THEN** the system immediately attempts rotation after Gitea is available,
  without waiting for the maximum age deadline

#### Scenario: Credential reaches maximum age

- **WHEN** the maximum credential age has elapsed and the replacement file
  contains a credential different from the last successfully applied one
- **THEN** the administrator password is changed to the replacement credential
  and the new rotation timestamp and non-reversible credential identity are
  persisted

#### Scenario: Activation does not change the credential

- **WHEN** configuration activation occurs and the replacement file identifies
  the same credential that was already applied
- **THEN** the system does not perform a redundant password change

#### Scenario: Credential is not yet expired

- **WHEN** a scheduled check runs before the maximum credential age elapses
- **THEN** the administrator credential is not changed and no new rotation
  metadata is written

#### Scenario: Replacement is unchanged

- **WHEN** rotation is due but the replacement file identifies the same
  credential that was already applied
- **THEN** the system does not perform a redundant password change and reports
  that a new replacement credential is required

### Requirement: Rotation is safe across failures and restarts

The system SHALL never invalidate the currently working administrator
credential before a replacement change succeeds. Failed checks or rotations
SHALL leave the last known-good credential usable, SHALL not advance the
rotation metadata, and SHALL be retried on a later scheduled check. Successful
rotation metadata SHALL survive recreation of the guest root filesystem.

#### Scenario: Replacement credential is unavailable

- **WHEN** rotation is due and the replacement file is missing, unreadable, or
  empty
- **THEN** rotation fails safely, the current credential remains usable, and
  the service records a failure for operator diagnosis without writing success
  metadata

#### Scenario: Gitea rejects the replacement

- **WHEN** the rotation operation returns an error
- **THEN** the current credential remains usable, the failure is visible in the
  service status or journal, and the next check can retry the operation

#### Scenario: Guest restarts after rotation

- **WHEN** the guest restarts after a successful rotation
- **THEN** the new credential remains usable, the old credential is rejected,
  and the persisted metadata prevents an immediate duplicate rotation

### Requirement: Rotation credentials are secret-safe

The system SHALL read replacement credentials at runtime from the configured
file and SHALL NOT place their contents in evaluated Nix configuration,
generated store paths, unit definitions, persistent metadata, or logs. The
persisted credential identity SHALL be non-reversible and SHALL not permit
reconstructing the credential.

#### Scenario: Replacement file uses a SOPS secret

- **WHEN** the replacement file references a decrypted `sops-nix` secret path
- **THEN** the rotation process reads the runtime secret while evaluation and
  generated configuration retain only the path reference

#### Scenario: Rotation command fails

- **WHEN** the underlying rotation command exits unsuccessfully
- **THEN** diagnostics omit the credential contents and the replacement file
  is not copied into persistent state

### Requirement: Rotation behavior is verified in a MicroVM

The Gitea MicroVM integration test SHALL exercise the expiration and rotation
workflow against a running service and an impermanent guest root. It SHALL
verify both successful rotation and safe failure behavior.

#### Scenario: End-to-end credential rotation

- **WHEN** the test advances or configures the expiration deadline and makes a
  new replacement credential available
- **THEN** the scheduled workflow rotates the administrator credential, the
  new credential authenticates, the old credential fails, and the metadata
  remains after a guest restart

#### Scenario: End-to-end failed rotation recovery

- **WHEN** the test reaches the expiration deadline without a usable
  replacement credential
- **THEN** the old credential continues to authenticate, the rotation reports
  failure, and supplying a valid replacement allows a later retry to succeed
