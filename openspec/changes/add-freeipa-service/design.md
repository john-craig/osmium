## Context

Osmium already runs Keycloak as a native service with declarative local users and
runtime secret rotation. The proposed Authelia service uses a YAML first-factor
backend but can select LDAP instead. This change introduces a shared FreeIPA
directory and changes both consumers' authentication boundaries; see `proposal.md`
and the eight change specifications for the behavior contract.

FreeIPA requires a stable fully-qualified hostname and correct forward/reverse
resolution. It packages LDAP, Kerberos, and internal certificate infrastructure
as a connected platform. The selected scope uses the directory and Kerberos
services while explicitly not exposing management of DNS, CA consumer issuance,
hosts, service principals, HBAC/sudo, or replicas.

## Goals / Non-Goals

**Goals:**

- Provide a single persistent FreeIPA LDAP and Kerberos authority with runtime
  administrator bootstrap and declarative user/group lifecycle.
- Use verified LDAPS bind connections for Keycloak federation and Authelia
  first-factor authentication.
- Preserve Keycloak's current local users and make Authelia's backend switch
  explicit and reversible.
- Apply the repository's secret-safe reconciliation, ownership, and
  runtime-derived reverse-configuration patterns.

**Non-Goals:**

- FreeIPA-integrated DNS, consumer certificate administration, host enrollment,
  service principals, HBAC, sudo, replicas, or high availability.
- Password synchronization or implicit migration from Keycloak or Authelia local
  users to FreeIPA.
- Simultaneous Authelia YAML and LDAP first-factor authentication.
- Weakening LDAPS validation, exposing directory bind credentials, or using the
  Directory Manager for routine Keycloak or Authelia bind requests.

## Decisions

### Run a single FreeIPA authority with external naming prerequisites

The service will own persistent FreeIPA state and bind explicit LDAP/LDAPS and
Kerberos ports. It will require the operator to supply a stable resolvable FQDN,
domain, and realm; MicroVM tests will model forward and reverse records locally.
The service does not manage authoritative DNS even though FreeIPA uses a CA and
service certificates internally for secure operation.

Integrated DNS was rejected because the user selected LDAP/Kerberos scope, and
because DNS zone authority changes network ownership. A no-CA deployment was
rejected because validated LDAPS requires a secure certificate and trust model.

### Bootstrap privileged credentials once and use restricted bind identities

Separate protected runtime files initialize the Directory Manager and normal IPA
administrator. A persistent secret-free ledger records completed bootstrap and
salted credential fingerprints. Managed non-human bind users for Keycloak and
Authelia have only the query permissions needed for the declared user/group
mapping subset; each consumes a distinct password file and rotates on changed
input.

Using Directory Manager credentials in consumers was rejected because that
credential bypasses routine directory authorization. A shared bind user was
rejected to avoid coupling independent consumer rotation and audit boundaries.

### Reconcile directory identities through supported FreeIPA interfaces

The module will use authenticated FreeIPA administrative interfaces/CLI for user,
group, membership, enablement, and password operations. It will maintain a
versioned ownership ledger and validate password replacement through LDAPS and
Kerberos prior to commit. Direct LDAP database manipulation is rejected because
it would bypass FreeIPA plugins, policy, and compatibility behavior.

### Federate Keycloak without changing local identities

Keycloak will receive a managed LDAP user-federation provider that points to
FreeIPA over LDAPS and consumes a runtime-only bind secret. Provider ownership
is separate from existing realms, users, roles, and client declarations. Local
users remain local, and collisions between local and federated identities fail
closed rather than choosing a backend implicitly.

### Switch Authelia atomically to LDAP mode

Authelia can have one first-factor backend. Enabling its FreeIPA integration
therefore renders LDAP configuration and disables use of the YAML backend while
retaining the YAML database in persistent state. A rollback is an explicit option
change that restores the retained file backend; it never alters FreeIPA users or
copies passwords between stores.

A merged or fallback backend was rejected because Authelia does not offer one and
would make authentication source and password ownership ambiguous. Automatic user
migration was rejected because it would require handling existing plaintext
password sources or forcing credentials without a confirmed user transition.

### Keep reverse configuration runtime-derived and review-only

FreeIPA observation will use supported administrative/LDAP/Kerberos inspection;
consumer observation will read Keycloak and Authelia runtime metadata. Reports
are normalized, provenance-tagged, incomplete when inputs are unavailable, and
exclude all credentials, hashes, keys, tickets, and tokens. Dedicated drift and
live-capture MicroVM checks will mutate runtime state, derive candidates from that
observation, and replay only representable behavior.

## Risks / Trade-offs

- **[FreeIPA boot and memory footprint are high]** → Allocate adequate MicroVM
  memory, wait for actual directory readiness, and keep the first feature scope
  narrow.
- **[Naming mistakes break Kerberos and LDAPS]** → Validate stable FQDN and
  forward/reverse resolution before readiness, model it in tests, and document
  the external DNS contract.
- **[CA lifecycle is essential but not exposed as a feature]** → Persist native
  FreeIPA CA state and trust consumers via a declared CA reference; defer
  consumer certificate management to a dedicated change.
- **[Authelia LDAP transition can lock out YAML-only users]** → Make it explicit,
  retain the YAML file for rollback, require valid LDAPS and bind validation
  before enabling LDAP mode, and test the rollback path.
- **[Directory/local username collisions create login ambiguity]** → Refuse
  collisions in Keycloak and document identity namespace requirements.

## Migration Plan

1. Ensure the operator-owned DNS provides a stable FQDN with matching forward and
   reverse records, then deploy FreeIPA with persistent state and protected
   bootstrap credentials.
2. Create directory users, groups, and dedicated consumer bind users; prove LDAP,
   Kerberos, and certificate trust before attaching consumers.
3. Enable Keycloak federation per realm. Verify FreeIPA OIDC login and group
   claims while retaining local Keycloak login paths.
4. Apply the base Authelia service change, retain its YAML database, then enable
   its FreeIPA LDAP mode only after a directory user and access-control policy are
   verified. Communicate that YAML-only logins stop in LDAP mode.
5. Roll back Keycloak by disabling its federation provider; roll back Authelia by
   explicitly selecting the retained YAML backend. Neither rollback mutates
   FreeIPA user credentials or removes its persistent state.
