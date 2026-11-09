## Why

Osmium needs a native authentication portal for applications that lack OpenID
Connect but can be protected by proxy authorization. Authelia provides this
without coupling its local identity store to the existing Keycloak deployment.

## What Changes

- Add a disabled-by-default `services.osmium.authelia` module using the pinned
  Nixpkgs Authelia package, explicit guest/host networking, SQLite persistence,
  readiness, and runtime-only secret inputs.
- Provide declarative local YAML users, groups, metadata, password-file inputs,
  and safe password hashing and rotation without placing plaintext passwords or
  generated hashes in the Nix store.
- Provide configurable TOTP policy and an optional one-time, runtime-secret
  TOTP bootstrap workflow using supported Authelia storage commands. TOTP
  bootstrap state and factor material remain secret-safe and persistent.
- Provide declarative default and per-domain access-control rules, plus the
  generic Authelia proxy-authorization endpoint needed by an external reverse
  proxy. Osmium will not configure or own protected routes or virtual hosts.
- Provide an explicit LLDAP LDAP authentication backend with typed directory,
  mapping, trust, and dedicated bind-secret declarations, including a safe
  transition and rollback boundary from the retained local YAML backend.
- Require the portal and forward-auth endpoints to be loopback-only and depend
  on an external TLS-terminating reverse proxy. The module will document the
  required forwarded headers and secure-cookie boundary.
- Add review-only drift detection and live capture for supported declarative
  users, groups, TOTP policy, and access-control attributes, with provenance,
  unresolved secret references, explicit completeness findings, and no live
  mutation.
- Add booting MicroVM integration checks for lifecycle, one- and two-factor
  authentication, proxy authorization, persistence, credential rotation, TOTP
  bootstrap, and both reverse-configuration directions.
- Document the deliberate boundary from Keycloak, OIDC-provider clients,
  bundled proxy routing, WebAuthn, and automatic external-proxy setup.

## Capabilities

### New Capabilities
- `authelia-service`: Native Authelia lifecycle, loopback networking, persistent
  SQLite storage, runtime secret handling, and external TLS-proxy boundary.
- `authelia-declarative-identities`: Declarative YAML users, groups, password
  rotation, and one-time TOTP bootstrap.
- `authelia-proxy-authorization`: Declarative access-control policy and secure
  generic forward-auth behavior for an externally managed reverse proxy.
- `authelia-lldap-authentication`: Explicit LLDAP first-factor authentication,
  group authorization, bind-secret rotation, and reversible backend transition.
- `authelia-reverse-configuration`: Review-only drift detection and live capture
  for supported Authelia declarative state.

### Modified Capabilities
- None.

## Impact

- New module: `modules/services/authelia.nix` and module import wiring.
- New MicroVM checks and flake outputs for service, identity/TOTP provisioning,
  proxy authorization, LLDAP authentication, drift conversion, and live-capture
  conversion.
- New documentation under `docs/authelia.md`.
- Runtime dependency on Authelia's file authentication backend, SQLite storage,
  storage CLI, and proxy authorization endpoint. TLS remains external to the
  MicroVM service and must not be represented as a service-owned certificate or
  virtual-host configuration.
