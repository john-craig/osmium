## Purpose

Provides deterministic, review-only conversion of supported Home Assistant
runtime state into secret-safe Osmium declarations.

## ADDED Requirements

### Requirement: Drift conversion covers supported Home Assistant attributes

The system SHALL compare declared and observed core configuration, supported
integrations, helpers, automations, scripts, scenes, blueprints, dashboards,
Lovelace resources, local user metadata, gateway configuration, and machine
credential status. It SHALL produce a deterministic reviewable candidate derived
from runtime observation with field-level findings, provenance, completeness,
unsupported-state reporting, and unresolved runtime-file requirements. It SHALL
NOT mutate Home Assistant, source files, ledgers, or services.

#### Scenario: Supported runtime configuration drifts

- **WHEN** a supported automation, script, scene, helper, dashboard, user
  metadata, or gateway setting changes in the running service
- **THEN** drift conversion reports that exact runtime difference and emits a
  candidate based on the observation rather than an independently authored
  fixture

#### Scenario: Drift includes secret or UI-only state

- **WHEN** observation encounters passwords, tokens, Keycloak secrets,
  device-backed configuration, opaque UI storage, or an unsupported integration
- **THEN** the candidate excludes secret values, records an actionable finding,
  and is incomplete when required state cannot be represented

### Requirement: Live capture covers supported Home Assistant attributes

The system SHALL capture supported configuration from the running service and
its managed configuration/state sources, distinguishing declared, unmanaged,
UI-only, device-backed, ambiguous, unsupported, and secret-backed state. It
MUST NOT invent configuration, source paths, user passwords, machine tokens, or
gateway credentials, and MUST NOT claim completeness for missing inputs.

#### Scenario: External supported state is captured

- **WHEN** a supported automation, script, scene, helper, or dashboard is
  created through the running service
- **THEN** capture emits its observable non-secret attributes with runtime
  provenance and explicit ownership status

#### Scenario: Hardware-backed state is captured

- **WHEN** capture encounters an integration requiring an unavailable host
  device, serial path, Bluetooth adapter, Zigbee/Z-Wave radio, or GPIO resource
- **THEN** it records the unsupported dependency and marks the affected
  declaration incomplete without fabricating a passthrough configuration

### Requirement: Reverse configuration is secret-safe and non-mutating

Drift and live capture MUST NOT request, export, log, hash for output, or persist
recovery passwords, local user passwords, access tokens, session cookies,
Keycloak client secrets, oauth2-proxy cookie secrets, credential digests, or
reversible derivatives. Commands SHALL write only to an operator-selected output
path or standard output and SHALL preserve service resources and lifecycle.

#### Scenario: Secret leakage is checked

- **WHEN** reverse configuration observes known test secrets and runtime gateway
  configuration
- **THEN** no secret or reversible derivative appears in candidates, findings,
  provenance, stdout, stderr, or persisted observation state

#### Scenario: Conversion completes

- **WHEN** a drift or live-capture candidate is generated
- **THEN** Home Assistant resources, configuration, ledgers, and services remain
  unchanged

### Requirement: Reverse paths are verified in dedicated MicroVM checks

The implementation SHALL provide separate booting checks named
`home-assistant-drift-reverse-configuration` and
`home-assistant-live-capture-reverse-configuration`. Each SHALL derive its
candidate from runtime-observed state, prove secret exclusion and non-mutation,
and exercise the represented behavior after unresolved inputs are supplied. The
commands SHALL be `nix build
.#checks.x86_64-linux.home-assistant-drift-reverse-configuration
--print-build-logs` and `nix build
.#checks.x86_64-linux.home-assistant-live-capture-reverse-configuration
--print-build-logs`.

#### Scenario: Drift reverse check runs

- **WHEN** the drift check mutates supported live configuration in a running
  MicroVM
- **THEN** it derives and verifies a candidate from that observation without
  altering the source service

#### Scenario: Live-capture reverse check runs

- **WHEN** the live-capture check creates supported state through the running
  service
- **THEN** it captures that state with provenance, reports incomplete or
  unsupported inputs, and verifies represented behavior in a replay MicroVM
