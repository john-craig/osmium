# LLDAP

`services.osmium.lldap` is a disabled-by-default, single-instance LDAP
directory built from the native NixOS `services.lldap` module and the pinned
`lldap` package. It is intended to provide shared users and groups to
Keycloak, and eventually to Authelia. It is not a FreeIPA replacement with
the same protocol or platform surface.

## Supported Scope

The module supports the LLDAP user and group subset exposed by its GraphQL
management API:

- LDAP naming through `baseDn`, stable user names and email addresses, display
  names, first names, last names, enabled state, and group memberships.
- Declarative `users` and `groups` reconciliation, with `retain` or `delete`
  removal policy and ownership recorded in the secret-free
  `/var/lib/lldap/.osmium-identities.json` ledger.
- LDAP and LDAPS listeners with explicit guest and host ports.
- A loopback HTTP administration and GraphQL listener, plus an optional
  Keycloak-protected HTTPS browser gateway.
- Review-only observation, capture, and drift tools when
  `reverseConfiguration.enable` is enabled. Their output is incomplete when
  runtime secret references or unsupported state cannot be represented.

The service does not provide Kerberos, DNS authority, host enrollment,
certificate issuance, HBAC or sudo policy, replicas, arbitrary LDAP schema
management, general LDAP write compatibility, or FreeIPA migration. Direct
SQLite writes and LDAP-based mutation are not supported; reconciliation uses
the authenticated LLDAP GraphQL API.

## Options And Runtime Secrets

The evaluated service options are under `services.osmium.lldap`:

- `enable`, `package`, and the fixed persistent `stateDir` (`/var/lib/lldap`).
- `baseDn`, `httpUrl`, `ldapHost`, `ldapPort`, `hostLdapPort`, `httpHost`,
  `httpPort`, and optional `hostHttpPort`.
- `admin.username`, `admin.email`, `admin.passwordFile`, and
  `admin.passwordRotation` (`bootstrap` or `always`).
- `jwtSecretFile` and `keySeedFile`.
- `ldaps.enable`, `ldaps.port`, `ldaps.hostPort`,
  `ldaps.certificateFile`, and `ldaps.keyFile`.
- `users.*.username`, `email`, `displayName`, `firstName`, `lastName`,
  `enabled`, `groups`, `passwordFile`, `removalPolicy`, and `consumer`.
  Consumer roles are `directory`, `keycloak`, and `authelia`; the latter is a
  declaration boundary until the Authelia integration is available.
- `groups.*.displayName`, `users`, and `removalPolicy`.
- `reverseConfiguration.enable`.
- `gateway.enable`, `gateway.keycloak.realm`, `gateway.keycloak.client`,
  `gateway.callbackUrl`, `gateway.clientSecretFile`,
  `gateway.cookieSecretFile`, `gateway.tls.certificateFile`,
  `gateway.tls.keyFile`, `gateway.browserPort`, `gateway.hostBrowserPort`,
  `gateway.machinePort`, `gateway.operator.allowedEmails`,
  `gateway.operator.groupClaimName`, and `gateway.operator.allowedGroups`.

All password, JWT, password-key, bind, cookie, and private-key values are
read from runtime files. They must not be embedded in Nix expressions,
generated settings, command arguments, ledgers, journals, or reverse
configuration. Runtime files must be outside `/nix/store`; the module also
requires distinct paths for values that must not be confused with one
another.

## Bootstrap, Reset, And Persistence

The initial administrator is bootstrapped from `admin.passwordFile`. With the
default `admin.passwordRotation = "bootstrap"`, a restart does not overwrite
an administrator password changed through the LLDAP UI. Set `"always"` only
when declarative administrator rotation is intentional; a changed file is
then consumed by the validated reset path. User and consumer bind-password
changes are validated through live authentication before the reconciliation
ledger records the new salted, non-reversible fingerprint.

The SQLite database, LLDAP service state, and ownership ledger persist below
`/var/lib/lldap` through the Osmium persistence configuration. The ledger does
not contain secret values. A blank, unreadable, malformed, or otherwise
rejected replacement must not be treated as a successful rotation and must
leave the last recoverable credential/state intact.

For recovery, stop the affected reconciliation or integration service, restore
the last known-good runtime secret file, and restart after checking the
service's readiness and live LDAP authentication. Preserve `/var/lib/lldap`
while recovering; deleting it destroys the directory state. If the directory
cannot be recovered, restore the persisted state and the matching secret-file
set together rather than rebuilding only the declarative ledger.

## LDAPS Trust

LDAPS is enabled by default and uses the declared runtime certificate and key
files. Consumers must use an `ldaps://` endpoint and a declared trust
certificate. Keycloak federation validates the trust certificate and performs
a live bind/search before reconciliation. Do not use an unverified LDAP
endpoint for a deployment; `LDAPTLS_REQCERT=never` is suitable only for
isolated tests. Certificate rotation must make the replacement available at
runtime and preserve the old working state until the new trust and endpoint
have been validated.

## Keycloak And The Administration Gateway

Keycloak federation is configured with one `ldapFederations.*` declaration per
realm. It uses an LLDAP consumer user, a dedicated bind-password file, an
`ldaps://` URL, a trust certificate, and the supported `uid`, `cn`, and
`member` mappings. Existing Keycloak-local users remain local. The federation
provider is read-only and is not allowed to use the LLDAP administrator
credential.

LLDAP has no native OpenID Connect client support and does not serve HTTPS for
its UI. When `gateway.enable` is used, nginx publishes the HTTPS browser
endpoint and oauth2-proxy performs the Keycloak authorization-code flow with
state, nonce, PKCE, operator email/group authorization, and runtime client and
cookie secrets. The LLDAP HTTP upstream remains loopback-only. Browser and
machine endpoints are separate: the gateway strips inbound and generated
identity headers, while GraphQL remains a separately authenticated machine
path and LDAP/LDAPS retain protocol authentication. Raw HTTP, public GraphQL,
and header-based authentication are not supported.

## Authelia Dependency And Blocker

Authelia LDAP authentication is planned against the `add-authelia-service`
base change, which is not yet complete in this repository. The current LLDAP
module does not enable or configure an Authelia backend. Do not infer
Authelia support from `users.*.consumer = "authelia"` alone.

Once the dependent module is available, the intended boundary is verified
LDAPS with a separate restricted bind user. Enabling LLDAP mode will retain
but disable Authelia's file backend; it will not migrate or modify credentials.
Disabling the integration must explicitly restore that retained file backend.
Until that implementation and its MicroVM check exist, the file backend is
the only supported Authelia path.

## Recovery And Rollback

Disable Keycloak's LLDAP federation and gateway route to roll back Keycloak;
local Keycloak users remain available. For the future Authelia integration,
explicitly disable LLDAP mode to restore the retained file backend. Rollback
does not delete `/var/lib/lldap`, mutate LLDAP credentials, or remove
unmanaged users and groups. Keep the directory and all runtime secret files
backed up as a compatible set, and review reverse-configuration candidates
before using any declaration derived from live state.

## FreeIPA Exclusions

The unfinished `add-freeipa-service` planning change is superseded by
`add-lldap-service` and is not enabled by this deployment. No FreeIPA module,
package adaptation, or FreeIPA flake check is selected in the module tree or
`flake.nix`. Deploy LLDAP only for the supported LDAP identity use case; do
not expect Kerberos, integrated DNS, CA management, host enrollment,
replicas, HBAC/sudo, service principals, or FreeIPA data migration.

Run the base service check with:

```sh
nix build .#checks.x86_64-linux.lldap --print-build-logs
```
