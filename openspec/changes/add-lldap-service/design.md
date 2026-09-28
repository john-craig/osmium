## Context

See `proposal.md` for motivation. LLDAP is a small Rust LDAP server with a
limited LDAP interface, a GraphQL management API, a single-page administration
UI, and SQL-backed state. The packaged NixOS module already manages a native
systemd service, a file-backed initial administrator password, and file-backed
JWT material. Unlike FreeIPA, it does not require a custom server derivation,
DNS authority, Kerberos, Dogtag, or host-management infrastructure.

LLDAP supports LDAPS but does not provide HTTPS or native OpenID Connect client
support for its HTTP administration interface. Its UI therefore has a browser
surface that must use the repository's Keycloak gateway pattern. LDAP and
GraphQL management credentials remain machine credentials and cannot be
substituted with browser sessions.

## Goals / Non-Goals

**Goals:**

- Compose NixOS LLDAP with Osmium's persistent MicroVM, secret-runtime,
  reconciliation, and explicit-port conventions.
- Provide a limited shared LDAP identity source for Keycloak and Authelia.
- Manage the supported user/group subset through LLDAP's GraphQL API without
  direct SQLite mutation.
- Make the browser administration boundary Keycloak-authenticated and
  testable, while retaining an independently authenticated machine API path.
- Provide deterministic, review-only reverse configuration for every supported
  declarative attribute.

**Non-Goals:**

- Kerberos, DNS, host enrollment, certificate issuance, HBAC/sudo, replicas,
  arbitrary LDAP schema or write support, multi-tenant virtual hosts, or
  FreeIPA data migration.
- Password synchronization or automatic migration of Keycloak-local or
  Authelia-file users into LLDAP.
- Public raw HTTP, public GraphQL, identity-header forwarding, or browser
  access to the machine-management endpoint.
- Replacing the pending `add-authelia-service` base change; this change depends
  on it or is applied with it.

## Decisions

### Compose the NixOS LLDAP module rather than package LLDAP separately

`services.osmium.lldap` will validate and translate a narrow typed Osmium
interface to the native NixOS LLDAP module. Initial storage is SQLite in a
persisted directory owned by the LLDAP service account. A PostgreSQL migration
is out of scope because it changes operational topology without being required
for the initial single-instance service.

The FreeIPA package adaptation is rejected because it was blocked at Dogtag
bootstrap and carries unneeded platform scope. A mutable container is rejected
because it would bypass native NixOS lifecycle and pinning controls.

### Separate immutable declarations, runtime secrets, and persistent state

The module will use systemd credentials or protected runtime files for the
initial administrator password, JWT secret, OPAQUE password key seed, LDAPS key
material, reconciliation API password, Keycloak bind password, Authelia bind
password, and Keycloak gateway client/cookie secrets. It will persist only
LLDAP state plus a secret-free, salted, non-reversible reconciliation ledger.

Bootstrap creates the initial LLDAP administrator once. Administrator changes
will use LLDAP's documented forced-reset behavior only when the operator opts
into a declarative rotation policy; a default bootstrap-only declaration must
not overwrite a UI-managed password on restart. Each changed secret triggers a
validate-before-commit reconciliation action where the upstream capability
permits one; otherwise the service fails closed and preserves recoverable state.

Putting secrets into Nix settings, generated TOML, environment files, command
arguments, or persistent ledgers is rejected because those surfaces can leak
through the store, process inspection, or diagnostics.

### Terminate TLS outside LLDAP and constrain every network boundary

LLDAP will bind the web/UI and GraphQL HTTP listener only to loopback. A local
TLS gateway will publish the declared HTTPS UI URL and validate TLS before
proxying to that upstream. LDAP and LDAPS will use declared guest and host
ports, with consumer integrations using verified LDAPS. The system will keep
browser and machine routes separate: browser access is Keycloak-gated, whereas
GraphQL stays loopback-only and is used by root-owned reconciliation tooling.

Direct LLDAP HTTPS was rejected because upstream does not support it. Exposing
raw UI or GraphQL on the network was rejected because it bypasses the
authentication and TLS boundary.

### Use the bounded Keycloak gateway for the LLDAP UI

The gateway will have its own Keycloak confidential client, callback path,
runtime client secret, runtime cookie secret, allowed operator authorization
rule, and state/nonce/PKCE checks. It will route only the browser UI endpoint
to the loopback upstream, strip all client-provided and gateway-generated
identity headers before proxying, and never treat LLDAP's session as a Keycloak
credential. Its failure behavior is deny-by-default. LDAP, LDAPS, and GraphQL
remain outside this route and retain their protocol-specific authentication.

A native OIDC integration is rejected because LLDAP does not provide one. A
transparent proxy with forwarded identity headers is rejected because LLDAP
does not define a trusted-header authentication contract.

### Reconcile LLDAP identities through GraphQL with a strict supported subset

Root-owned lifecycle tooling will authenticate to the local GraphQL endpoint
using a dedicated managed machine administrator or API credential. It will
reconcile users, groups, supported metadata, and memberships in dependency
order, retaining a versioned ownership ledger. Dedicated least-privilege LDAP
bind users are separate from the LLDAP administrator and from each other for
Keycloak and Authelia. Consumers only receive their own runtime secret files.

Direct database writes and LDAP-based mutation are rejected because LLDAP's
LDAP support is intentionally limited and direct SQL bypasses its application
invariants. Unmanaged identities are not adopted; ambiguous removal fails
closed.

### Integrate consumers without changing their local identity guarantees

Keycloak receives one managed LLDAP LDAP federation provider per declaration,
verifies the LDAPS endpoint and trust chain, and keeps local users local.
Authelia receives one LDAP backend mode; selecting it retains but disables the
file backend, and deselecting it explicitly restores the retained backend.
No path migrates or synchronizes password values.

### Make reverse configuration observation-derived and replayable

Drift and capture commands will query LLDAP GraphQL/LDAP plus relevant
Keycloak/Authelia metadata read-only. Candidates will identify live
provenance, ownership, unavailable secret file references, and unsupported
state. They will never output passwords, password material, JWTs, cookies,
API tokens, private keys, or hashes. A candidate whose required inputs cannot
be represented is marked incomplete and review-only. Dedicated MicroVM checks
will mutate live state before conversion and replay representable behavior from
the produced candidate rather than a hand-written equivalent declaration.

## Risks / Trade-offs

- **[LLDAP supports only a limited LDAP subset]** -> Restrict declarations and
  tests to upstream-supported users, groups, memberships, authentication, and
  search mappings; reject unsupported schema or write behavior.
- **[LLDAP upstream has no HTTPS or OIDC client]** -> Require the Keycloak
  gateway for the UI and test login, denial, bypass, header stripping, and
  machine-endpoint separation in a booting MicroVM.
- **[Bootstrap password behavior can overwrite UI state]** -> Make forced reset
  an explicit rotation mode and validate its effects in the lifecycle check.
- **[SQLite is a single-instance database]** -> Scope the service to one
  persistent MicroVM and defer high availability or external SQL migration.
- **[Keycloak or Authelia integration can lock users out]** -> Validate LDAP and
  TLS before enabling, retain Keycloak local accounts and Authelia's file
  backend, and test explicit rollback.

## Migration Plan

1. Mark `add-freeipa-service` superseded and do not deploy its module or run its
   incomplete check alongside LLDAP.
2. Deploy LLDAP with a persisted state directory and all required runtime
   secrets, then verify LDAP and the Keycloak-gated administration UI.
3. Provision LLDAP users, groups, and separate Keycloak/Authelia bind users;
   verify LDAPS trust before enabling either consumer.
4. Enable Keycloak federation per realm and confirm both federated and local
   login behavior. Enable Authelia LDAP mode only after verifying a directory
   user and access policy; retain the file backend for rollback.
5. Roll back Keycloak by disabling its LLDAP provider and gateway route. Roll
   back Authelia by explicitly selecting the retained file backend. Neither
   rollback mutates LLDAP credentials or deletes persistent state.
