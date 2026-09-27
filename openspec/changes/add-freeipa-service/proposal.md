## Why

Osmium needs a shared standards-based identity directory for services that use
LDAP or Kerberos. FreeIPA provides an authoritative local directory that
Keycloak can federate and Authelia can use as its primary first-factor backend.

## What Changes

- Add a disabled-by-default `services.osmium.freeipa` service using the pinned
  Nixpkgs FreeIPA package with explicit domain, realm, hostname, guest/host
  networking, persistent LDAP/Kerberos state, runtime bootstrap credentials, and
  readiness checks.
- Add declarative FreeIPA users and groups with runtime password-file inputs,
  secret-safe one-time administrator bootstrap, changed-secret password rotation,
  ownership tracking, and safe removal behavior.
- Restrict the initial FreeIPA service scope to LDAP and Kerberos identities and
  groups. Integrated DNS management, host enrollment, service principals,
  sudo/HBAC policy, certificate issuance management, and replica/high-availability
  management remain out of scope.
- Add Keycloak LDAP user-federation declarations that use FreeIPA over validated
  TLS with a dedicated runtime-only bind account. FreeIPA users SHALL authenticate
  through Keycloak while existing declared Keycloak-local users remain unchanged.
- Add Authelia LDAP-backend declarations that use FreeIPA over validated TLS with
  a dedicated runtime-only bind account. **BREAKING for enabled Authelia LDAP
  integration:** Authelia switches from its YAML file backend to FreeIPA LDAP;
  existing YAML records are retained only for rollback and cannot authenticate
  while LDAP mode is enabled.
- Add review-only drift detection and live capture for FreeIPA declarative users,
  groups, and supported integration metadata, with provenance, unresolved secret
  references, explicit incompleteness, and no mutation.
- Add booting MicroVM checks for FreeIPA lifecycle, bootstrap and rotation,
  LDAP/Kerberos behavior, Keycloak federation, Authelia LDAP authentication, and
  reverse configuration.
- Document the stable-FQDN and external DNS requirements, TLS trust model,
  Keycloak/Authelia migration boundaries, recovery, and excluded FreeIPA features.

## Capabilities

### New Capabilities
- `freeipa-service`: Native FreeIPA LDAP and Kerberos lifecycle, persistence,
  runtime bootstrap, stable naming, TLS, and explicit networking.
- `freeipa-declarative-identities`: Declarative FreeIPA users, groups, runtime
  credentials, rotation, ownership, and safe lifecycle management.
- `freeipa-reverse-configuration`: Review-only drift and live-capture conversion
  for supported directory identities and integration metadata.
- `keycloak-freeipa-federation`: FreeIPA LDAP federation for Keycloak while
  preserving existing Keycloak-local users.
- `authelia-freeipa-authentication`: FreeIPA LDAP first-factor authentication for
  Authelia with the explicit file-backend transition boundary.

### Modified Capabilities
- `keycloak-service`: Add the FreeIPA network, TLS, and lifecycle dependency
  behavior required for an enabled federation.
- `keycloak-declarative-configuration`: Add typed LDAP federation declarations
  and preserve local-user reconciliation alongside federated identities.
- `keycloak-reverse-configuration`: Add review-only observation and candidate
  conversion for supported FreeIPA federation metadata.

## Impact

- New module: `modules/services/freeipa.nix`, module import wiring, FreeIPA
  documentation, and FreeIPA-focused MicroVM checks.
- Extensions to `modules/services/keycloak.nix` and the Authelia module planned
  by `add-authelia-service`; this change must be applied after that base Authelia
  service change or together in a coordinated implementation.
- FreeIPA package version currently available in Nixpkgs: `freeipa` 4.13.1.
- Runtime dependency on FreeIPA's LDAP, Kerberos, administrative CLI/API, CA
  trust chain, plus Keycloak LDAP federation and Authelia LDAP support.
- Operators must arrange a stable resolvable FQDN and matching reverse resolution
  outside this service because FreeIPA's integrated DNS management is not included.
