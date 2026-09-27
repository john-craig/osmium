## Purpose

Manage Homebox users, collections, memberships, and API keys through a bounded hybrid of supported APIs and runtime database bootstrap operations.

## ADDED Requirements

### Requirement: Version-gated identity bootstrap
The system SHALL manage declared users, groups, memberships, and API-key ownership through supported Homebox APIs where possible and a runtime database helper only where APIs cannot express the desired state. The helper SHALL verify the application and schema version before mutating data and SHALL fail closed on unsupported versions.

#### Scenario: Supported version is bootstrapped
- **WHEN** Homebox is running with a recognized application/database schema version
- **THEN** the bootstrap helper reconciles the declared identity state and records ownership without embedding credentials in the Nix store

#### Scenario: Unsupported schema fails closed
- **WHEN** the helper cannot prove compatibility with the running Homebox schema
- **THEN** it performs no identity mutation and reports the required version or migration action

### Requirement: Declarative users and groups
The system SHALL reconcile declared users, collection groups, and memberships by stable identity, SHALL preserve unmanaged identities, SHALL reject ambiguity, and SHALL avoid destructive deletion by default.

#### Scenario: User and group are created once
- **WHEN** a declared user or group is absent and bootstrap is enabled
- **THEN** it is created once, its UUID is recorded in the ownership ledger, and later activations do not create duplicates

#### Scenario: Membership is reconciled
- **WHEN** a declared user is absent from an owned group
- **THEN** the helper adds the membership through the supported invitation/API path or the version-gated runtime database path and verifies the resulting role

#### Scenario: Unmanaged identity is preserved
- **WHEN** Homebox contains a user, group, or membership not owned by the declaration
- **THEN** reconciliation leaves it unchanged

### Requirement: Runtime-only credentials
The system SHALL consume local passwords, OIDC client secrets, bootstrap authentication credentials, and API-key output paths only at runtime and SHALL exclude secret values from evaluated configuration, generated service files, logs, and reverse-configuration output.

#### Scenario: Credential bootstrap is secret-safe
- **WHEN** an identity requires a runtime credential
- **THEN** the helper reads it from a protected runtime input and the value is absent from the Nix store, logs, and generated declaration

### Requirement: API-key lifecycle
The system SHALL support one owned API key per declared user where the running Homebox version supports it, SHALL persist successful bootstrap state, SHALL not create duplicate keys on unchanged activations, and SHALL rotate the owned key when the configured runtime rotation secret-file value changes.

#### Scenario: API key is created once
- **WHEN** a declared user has no owned API key and bootstrap is enabled
- **THEN** the helper creates one at runtime, records only non-secret ownership metadata, delivers the raw key through the protected output path, and reuses the ownership record on later activations

#### Scenario: Changed rotation secret triggers replacement
- **WHEN** the configured API-key rotation secret-file value changes
- **THEN** the helper consumes the new runtime value, revokes only the owned key, creates a replacement key, and delivers the replacement through the protected output path

#### Scenario: Ownership cannot be proven
- **WHEN** a matching API key cannot be proven to be owned by the declaration
- **THEN** the helper does not revoke or replace it automatically and reports an actionable failure

### Requirement: Identity reverse configuration
The system SHALL provide review-only drift conversion and live capture for supported users, groups, memberships, and API-key metadata while omitting passwords, raw API keys, sessions, invitations, and OIDC secrets.

#### Scenario: Identity drift is converted
- **WHEN** owned identity or membership state differs from the declaration
- **THEN** drift detection produces a reviewable declaration conversion without mutating Homebox or including secret material

#### Scenario: Live identity capture is incomplete where necessary
- **WHEN** live capture observes secret-only or unsupported identity state
- **THEN** it records provenance, omits the secret, identifies the required runtime input, and marks the declaration incomplete
