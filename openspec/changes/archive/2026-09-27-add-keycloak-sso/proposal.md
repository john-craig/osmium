## Why

Osmium services currently maintain separate local credentials and provide no
shared identity boundary. A declarative Keycloak service is needed so an
impermanent deployment can reproduce realms, signing material, clients, roles,
groups, users, and credentials without placing secrets in evaluated Nix state,
and applicable browser-facing services can use one tested single sign-on flow.

## What Changes

- Add a native, disabled-by-default Keycloak service in an isolated MicroVM with
  explicit networking, PostgreSQL-backed persistent state, readiness, and
  secret-safe one-time administrator bootstrap.
- Add typed declarations for realms, realm signing keys, clients, client
  scopes, realm/client roles, groups, users, role/group mappings, user password
  credentials, and confidential-client credentials.
- Reconcile all secret material from runtime files, record only non-secret
  completion state, and rotate administrator, user, client, and signing
  credentials when their declared secret-file values change.
- Add review-only drift conversion and live-system capture for supported
  Keycloak declarations, with deterministic output, provenance, explicit
  incompleteness, unsupported-state reporting, and secret placeholders.
- Add opt-in Keycloak SSO integration for Gitea through its native OpenID
  Connect provider support and for Gotify and OpenCode browser access through a
  shared OIDC-aware ingress pattern. Preserve explicit machine/API
  authentication paths rather than forcing interactive redirects on clients.
- Define F-Droid repositories and filesystem snapshot tooling as out of scope
  for interactive SSO: F-Droid clients require direct repository access and
  snapshot tooling has no browser login surface. Keep this boundary explicit in
  validation, documentation, and tests.
- Add booting MicroVM integration checks for Keycloak lifecycle, credential and
  signing-key rotation, drift conversion, live capture, and an end-to-end login
  through Keycloak to each applicable existing service.
- Update `AGENTS.md` so future service proposals and implementations MUST add
  Keycloak SSO when upstream or a safe gateway makes it practical, and MUST
  document and test any exemption.

## Capabilities

### New Capabilities

- `keycloak-service`: Native Keycloak deployment, networking, PostgreSQL state,
  administrator bootstrap, persistence, readiness, and MicroVM lifecycle.
- `keycloak-declarative-configuration`: Typed realm, key, client, role, group,
  user, mapping, and credential reconciliation with runtime-only secrets and
  changed-file rotation.
- `keycloak-reverse-configuration`: Review-only drift conversion and live
  capture for supported Keycloak state.
- `keycloak-service-sso`: Opt-in, end-to-end tested Keycloak SSO for applicable
  Osmium browser services, explicit machine-authentication boundaries, and
  documented exemptions.

### Modified Capabilities

- `gotify-service`: Add an optional Keycloak-authenticated browser ingress while
  retaining Gotify token authentication for notification and API clients.
- `opencode-server-service`: Add an optional Keycloak-authenticated browser
  ingress while retaining a separately bounded runtime-authenticated API path.

## Impact

- Adds a Keycloak service module, runtime reconciliation and observation tools,
  a PostgreSQL dependency, protected secret-file inputs, persisted reconciliation
  state, an example guest, and flake checks.
- Extends the Gitea, Gotify, and OpenCode service modules with opt-in SSO/client
  declarations and network exposure rules; existing configurations remain
  unchanged while SSO is disabled.
- Adds an OIDC proxy package/service for applications without native OIDC and
  introduces browser-session cookie secret files for those gateways.
- Adds coordinated multi-MicroVM tests that run a real Keycloak instance and
  authenticate test users against each applicable service.
- Changes repository contributor policy in `AGENTS.md` for future services.
