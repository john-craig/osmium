# Keycloak

`services.osmium.keycloak` is disabled by default. Enable it only with runtime
secret files for the administrator, database, TLS, user, and confidential
client credentials. Secret values must not be placed in Nix expressions,
generated JSON, ledgers, or reverse-configuration output.

The module persists Keycloak and reconciliation state below `stateDir` and
exposes read-only observation tools when `reverseConfiguration.enable` is set:

```sh
osmium-keycloak-observe --output /run/keycloak-observation.json
osmium-keycloak-candidate --input /run/keycloak-observation.json
```

Candidates are incomplete by design when secret-backed file references or
unsupported live state cannot be reconstructed. Review them before activation;
the tools do not adopt or mutate Keycloak resources.

The native module uses the pinned nixpkgs Keycloak package and local PostgreSQL.
Production issuers must use HTTPS. `allowInsecureHttp` is reserved for isolated
tests and must not be used for a public deployment. TLS material is referenced
by path and is never copied into the persistent ledger.

The reconciler currently owns realms, OpenID Connect clients, client scopes,
realm roles, client roles, groups, user accounts, group membership, and realm
role mappings. It applies these resources in dependency order through the live
administrative API and writes only non-secret desired state to the ledger.
Client and user password files are consumed at runtime. A failed credential
update aborts reconciliation before the success ledger is written; administrator
rotation, signing-key overlap, and destructive removal policies are not yet
implemented and must not be assumed from the declarations.

Observation is read-only and queries the live administrative and JWKS endpoints.
It excludes all password, client-secret, private-key, token, and database
material. The candidate output is deliberately incomplete and contains
unresolved runtime file references. It is a review artifact, not an adoption or
activation command.

Run the native check with:

```sh
nix build .#checks.x86_64-linux.keycloak --print-build-logs
```

Services without native OIDC must use a bounded gateway and retain their
existing token or Basic-auth endpoint. F-Droid repository clients are exempt
because redirects break repository protocol clients; filesystem snapshot
tooling has no browser login surface.
