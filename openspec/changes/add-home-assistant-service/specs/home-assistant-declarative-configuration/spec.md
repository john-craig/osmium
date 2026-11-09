## Purpose

Provides typed, reproducible Home Assistant configuration and supported local
identity management while distinguishing declarative state from UI-only state.

## ADDED Requirements

### Requirement: Supported Home Assistant configuration is declarative

The system SHALL expose typed declarations for Home Assistant core settings,
YAML-backed integrations, helpers, automations, scripts, scenes, blueprints,
Lovelace dashboards and resources, and supported UI configuration. Stable
declaration keys and explicit source order SHALL make rendered configuration
deterministic. Invalid schemas, duplicate stable identities, unsafe includes,
and unsupported device-backed configuration MUST fail before activation.

#### Scenario: Complete configuration is rendered

- **WHEN** a valid declaration includes core configuration, an integration,
  helper, automation, script, scene, blueprint, dashboard, and Lovelace resource
- **THEN** the running service exposes each supported element with its declared
  identity and behavior after configuration reload or restart

#### Scenario: Configuration declaration is invalid

- **WHEN** a declaration has a duplicate identity, unsupported YAML structure,
  unsafe path, or hardware-dependent input
- **THEN** evaluation fails with the offending declaration path and no partial
  configuration is activated

### Requirement: Local users and recovery credentials are declarative

The system SHALL support declarations for a native recovery owner, restricted
gateway user, and supported local non-owner users with stable usernames,
display metadata, role, enabled state, and optional protected runtime password
files. Password contents SHALL remain runtime-only. A missing optional user
password SHALL leave the user activation incomplete rather than generate a
credential. User changes MUST preserve the native recovery owner unless an
explicit safe rotation is requested.

#### Scenario: Local user is provisioned

- **WHEN** a valid local-user declaration references a protected password file
- **THEN** Home Assistant creates or matches the intended account with the
  declared supported role and the user authenticates with its native credential

#### Scenario: Local credential rotates

- **WHEN** a declared local user's password file receives a valid replacement
- **THEN** the new native credential succeeds, the prior credential fails, and
  unrelated user accounts remain unchanged

#### Scenario: User configuration is incomplete

- **WHEN** a non-recovery user declaration omits its optional password file
- **THEN** the service records an unresolved native setup requirement without
  generating, logging, or persisting a password

### Requirement: Machine authentication remains explicit and separate

The service SHALL support protected runtime declarations for Home Assistant
long-lived access tokens or equivalent supported machine credentials. Machine
credentials SHALL be scoped to declared local users, generated or consumed at
runtime, persisted only where Home Assistant requires it, and excluded from
declarative output. Browser gateway sessions MUST NOT grant machine API access.

#### Scenario: Machine client calls the API

- **WHEN** an automation client supplies a current declared Home Assistant
  machine credential to the machine endpoint
- **THEN** the protected API succeeds without an interactive browser redirect

#### Scenario: Stale machine credential is rejected

- **WHEN** a caller omits or supplies a stale machine credential
- **THEN** Home Assistant rejects the request without accepting browser headers
  or a Keycloak gateway session as machine authority

### Requirement: Declarative state is owned, idempotent, and safe to update

The system SHALL maintain a versioned secret-free ownership ledger for rendered
and API-managed supported state. Reconciliation SHALL be ordered and idempotent,
and shall update only managed identities/configuration. Removal SHALL require an
explicit policy where destructive behavior is supported; unmanaged, UI-only,
ambiguous, or unsupported state MUST remain unchanged and be reported.

#### Scenario: Reconciliation repeats

- **WHEN** the same supported configuration and user declarations reconcile
  twice
- **THEN** the service retains one instance of each declared element and does
  not duplicate users, automations, scripts, scenes, or dashboards

#### Scenario: Managed state becomes ambiguous

- **WHEN** a supported runtime resource cannot be matched to its declaration and
  ownership ledger
- **THEN** reconciliation fails closed without deleting, replacing, or adopting
  the resource

### Requirement: Declarative configuration is exercised in a MicroVM

The implementation SHALL provide a booting MicroVM check that loads supported
core configuration, integration, helper, automation, script, scene, blueprint,
dashboard, user, and machine-token declarations; verifies persistence,
idempotence, rotation, and failure preservation; and rejects hardware passthrough.
The executable command SHALL be `nix build
.#checks.x86_64-linux.home-assistant-declarative-configuration
--print-build-logs`.

#### Scenario: Declarative configuration check runs

- **WHEN** the configuration check executes
- **THEN** it validates behavior through the running Home Assistant service and
  API rather than only inspecting rendered configuration files
