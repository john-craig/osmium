## Why

The FreeIPA service proposal is not yet viable: its server package adaptation
and Dogtag CA bootstrap remain blocked. Osmium needs a smaller, native LDAP
directory that can provide shared users and groups to Keycloak and Authelia
without FreeIPA's DNS, Kerberos, certificate-authority, and host-management
requirements.

## What Changes

- Supersede the unfinished `add-freeipa-service` change with a disabled-by-
  default `services.osmium.lldap` service built on the NixOS `services.lldap`
  module and the pinned `lldap` package.
- Add typed declarations for LDAP naming, LDAP and HTTPS guest/host networking,
  persistent database state, runtime-only bootstrap and cryptographic secret
  files, and the externally terminated HTTPS administration endpoint.
- Add declarative LLDAP users and groups, lifecycle reconciliation through the
  supported GraphQL API, runtime password files, changed-secret rotation,
  ownership tracking, and safe removal behavior.
- Use TLS-terminated LDAP for Keycloak federation and Authelia first-factor
  authentication. LLDAP does not provide Kerberos, DNS, host enrollment,
  certificate issuance, HBAC/sudo, LDAP write compatibility, or general LDAP
  schema management; those FreeIPA-specific features are explicitly removed
  from scope.
- Assess LLDAP's native browser authentication: its administration interface
  has no OpenID Connect client support. Protect it with the bounded Keycloak
  gateway pattern, using a loopback-only LLDAP HTTP upstream, separate browser
  and machine endpoints, runtime-only client/cookie secrets, and stripped
  identity headers. Keep LDAP and GraphQL machine credentials outside the
  browser gateway.
- Add review-only drift detection and live capture for supported LLDAP
  declarations, including provenance, incompleteness, and secret exclusion.
- Add booting MicroVM checks for LLDAP bootstrap, persistence, credential
  rotation, LDAP and HTTPS boundaries, Keycloak and Authelia integrations,
  browser-gateway login/denial/bypass behavior, and reverse configuration.

## Capabilities

### New Capabilities
- `lldap-service`: Native LLDAP lifecycle, persistence, secret-safe bootstrap,
  TLS and network boundaries, and Keycloak-protected administration UI.
- `lldap-declarative-identities`: Declarative LLDAP users and groups, runtime
  credentials, reconciliation, ownership, rotation, and safe removal.
- `lldap-reverse-configuration`: Review-only drift and live-capture conversion
  for supported directory identities and integration metadata.
- `keycloak-lldap-federation`: LLDAP LDAP federation for Keycloak while
  preserving existing Keycloak-local users.
- `authelia-lldap-authentication`: LLDAP LDAP first-factor authentication for
  Authelia with the explicit file-backend transition boundary.

### Modified Capabilities
- `keycloak-service`: Add the LLDAP network, TLS, lifecycle dependency, and
  LLDAP administration gateway behavior required by enabled integrations.
- `keycloak-declarative-configuration`: Add typed LLDAP federation and bounded
  LLDAP administration-gateway declarations while preserving local-user
  reconciliation.
- `keycloak-reverse-configuration`: Add review-only observation and candidate
  conversion for supported LLDAP federation and gateway metadata.

## Impact

- New LLDAP module, documentation, module imports, and MicroVM checks;
  `add-freeipa-service` remains superseded and must not be applied alongside
  this change.
- Extends Keycloak and the Authelia module planned by `add-authelia-service`;
  this change depends on that base Authelia service or a coordinated apply.
- Uses NixOS's native `services.lldap` module and `lldap` package (currently
  `0.6.3`) with SQLite initially, rather than a custom package adaptation or a
  mutable container image.
- Introduces runtime dependencies on LLDAP LDAP/GraphQL APIs, a TLS termination
  layer for LDAPS and HTTPS, Keycloak LDAP federation, and Authelia LDAP
  support.
