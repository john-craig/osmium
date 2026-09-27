## Why

Osmium needs a reproducible Home Assistant MicroVM whose automation and UI
configuration can be reviewed, restored across impermanent guest recreation,
and safely exposed to household browsers. Home Assistant does not provide a
core native OpenID Connect provider, so browser access requires the repository's
bounded Keycloak gateway pattern while preserving native recovery and machine
authentication paths.

## What Changes

- Add a disabled-by-default `services.osmium.homeAssistant` module using the
  pinned Nixpkgs Home Assistant package, explicit persistence, networking,
  lifecycle, and runtime-only credentials.
- Add typed declarative configuration for Home Assistant core settings,
  authentication/recovery users, integrations, automations, scripts, scenes,
  blueprints, Lovelace dashboards/resources, helpers, and supported YAML-backed
  configuration.
- Add a secure one-time owner and restricted gateway-user bootstrap flow using
  runtime credentials, with changed-secret rotation and secret-free completion
  metadata wherever Home Assistant's native APIs permit it.
- Add a bounded Keycloak browser gateway: Home Assistant binds only to loopback;
  nginx and oauth2-proxy gate browser access; Keycloak-authenticated browsers
  receive the shared restricted Home Assistant gateway user; native Home
  Assistant recovery users and separately declared long-lived access tokens
  remain the only machine/recovery paths.
- Add declarative management of supported local user roles, recovery credentials,
  and machine API tokens, with explicit recognition that the browser gateway
  intentionally does not map Keycloak subjects to per-user Home Assistant
  identities.
- Add reverse configuration for every supported declarative Home Assistant
  attribute: deterministic drift conversion and live capture with provenance,
  completeness, secret exclusions, and review-only candidates.
- Explicitly defer USB, serial, Bluetooth, Zigbee, Z-Wave, GPIO, and other
  device passthrough to a future change.
- Add booting MicroVM checks for lifecycle, declarative configuration,
  Keycloak browser login/denial/bypass boundaries, recovery and machine tokens,
  credential rotation, persistence, drift conversion, and live capture.

## Capabilities

### New Capabilities

- `home-assistant-service`: Native Home Assistant service lifecycle,
  persistence, runtime credential bootstrap, explicit networking, and device
  passthrough exclusion.
- `home-assistant-declarative-configuration`: Typed, declarative Home Assistant
  core configuration, automations, scripts, scenes, blueprints, dashboards,
  integrations, helpers, local users, and machine credentials.
- `home-assistant-keycloak-sso`: Bounded Keycloak browser gateway with a shared
  restricted Home Assistant user and separate native recovery/machine paths.
- `home-assistant-reverse-configuration`: Review-only runtime drift and live
  capture for supported Home Assistant declarations.

### Modified Capabilities

- None.

## Impact

- New service module, module import, documentation, MicroVM tests, and flake
  check outputs.
- Uses native NixOS `services.home-assistant` configuration plus nginx and
  oauth2-proxy for browser SSO.
- Integrates with the existing Keycloak module and its runtime client/cookie
  secrets, requiring a managed confidential client and a booting Keycloak login
  check.
- Does not pass through host devices in this change; hardware-dependent
  integrations remain unavailable until a later capability is specified.
