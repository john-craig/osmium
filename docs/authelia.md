# Authelia

`services.osmium.authelia` is a disabled-by-default, single-instance Authelia
service. It provides the authentication service only. TLS termination,
public DNS, reverse-proxy routes, and application upstreams remain the
responsibility of an external proxy.

## Runtime Boundary

The module requires an HTTPS `portalUrl` and binds Authelia to loopback by
default at `127.0.0.1:9091`. It does not create certificates, public virtual
hosts, Nginx configuration, oauth2-proxy, Keycloak, or an OpenID Connect
provider. Forwarded HTTPS metadata is intended to arrive from the local
proxy boundary; raw guest-network access is not a supported deployment path.

The persistent state directory is fixed at `/var/lib/authelia` and contains
the SQLite database, generated file-backend users, notifications, and
Osmium's protected reconciliation ledger. SQLite is a single-instance
backend; do not share it between Authelia instances.

## Secrets And Local Users

The runtime-only options are `jwtSecretFile`, `storageEncryptionKeyFile`,
`sessionSecretFile`, user `passwordFile` values, and optional TOTP bootstrap
paths. Every secret path must be absolute and outside `/nix/store`. Secret
bytes and generated password hashes are consumed at runtime and are excluded
from evaluated settings, the Nix store, logs, and reverse-configuration
output.

Users are declared under `users.*` with `username`, `displayName`, `email`,
`enabled`, `groups`, and `passwordFile`. Groups are declared under `groups.*`
with `displayName` and `users`. The reconciliation service hashes passwords,
renders the writable YAML backend atomically, and records only salted
fingerprints and hashes in the protected ledger. A changed password file is
validated before the new state is committed. Restore the previous runtime
file and restart `osmium-authelia-reconcile.service` after a failed rotation.

## TOTP

Set `totp.defaultMethod = "totp"` when the deployment requires TOTP by
default. A user's `totp.bootstrapFile` enables one-time factor creation;
`totp.outputFile` can receive protected enrollment output. Completion is
recorded without storing the TOTP secret in the Osmium ledger. Existing
factors are not replaced by reconciliation.

## Access Control And Proxying

`accessControl.defaultPolicy` defaults to `deny`. Ordered
`accessControl.rules` support `bypass`, `one_factor`, `two_factor`, and
`deny`, with optional domains, resources, and subjects. The generated
`/api/authz/forward-auth` endpoint is the generic authorization interface for
an external proxy. The proxy must forward the original HTTPS scheme, host,
URI, and method. Do not treat an inbound identity header as authentication.

## LLDAP Backend

Set `ldap.enable = true` only when `services.osmium.lldap.enable` is also
enabled. Use a dedicated restricted `bindDn` and `bindPasswordFile`; never
reuse the LLDAP administrator credential. LDAP filters and attribute mappings
are declared under `ldap.*`. TLS mode requires an explicit runtime trust
certificate. The integration is intended to retain the file backend for
explicit rollback rather than migrate or mutate local credentials.

## Reverse Configuration

With `reverseConfiguration.enable = true`, the system provides
`osmium-authelia-observe`, `osmium-authelia-candidate`, and
`osmium-authelia-drift`. These tools are review-only. They report provenance,
unresolved runtime secret references, unsupported state, and incomplete
coverage instead of exporting passwords, hashes, keys, cookies, tokens, or
TOTP values. Candidate output must be reviewed before it is used as a
declaration.

## Checks

The base, identity, and proxy behavior are exercised in MicroVM checks:

```sh
nix build .#checks.x86_64-linux.authelia --print-build-logs
nix build .#checks.x86_64-linux.authelia-identities --print-build-logs
nix build .#checks.x86_64-linux.authelia-proxy-authorization --print-build-logs
```

LLDAP authentication, TOTP, and reverse-configuration lifecycle checks must
also pass before those capabilities are considered complete.
