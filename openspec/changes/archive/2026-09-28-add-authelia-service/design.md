## Context

The repository's service modules use native NixOS services, impermanent MicroVMs,
runtime secret files, secret-free reconciliation state, and booting integration
checks. New declarative module attributes also require review-only drift and
live-capture conversions. See `proposal.md` and the four change specifications
for the behavioral contract.

Authelia supports a writable local YAML authentication backend, SQLite-backed
state, encrypted TOTP factor storage, a storage CLI for factor administration,
and proxy authorization. Its portal and forward-auth cookie model require HTTPS,
but the selected deployment boundary delegates TLS termination and public routing
to an external proxy.

## Goals / Non-Goals

**Goals:**

- Compose the native Authelia service with a local file backend, persistent
  SQLite state, runtime-only secret material, and explicitly loopback-only
  listeners.
- Reconcile only the selected user, group, TOTP, and access-control subset while
  preserving the file backend's required writable semantics.
- Make password rotation and first-time TOTP bootstrap safe, idempotent, and
  observable through live MicroVM behavior.
- Provide generic, standard proxy authorization without taking ownership of the
  public proxy or application routes.
- Provide an explicit LLDAP backend integration with strict trust validation,
  dedicated bind credentials, and an explicit rollback to the retained local
  YAML backend.
- Derive review-only reverse declarations from observed runtime state.

**Non-Goals:**

- Keycloak federation, shared users, SSO gateway composition, or any other
  relationship with the existing Keycloak service.
- Authelia OpenID Connect provider/client configuration, Duo, WebAuthn, password
  reset delivery, or a highly available database/cache architecture.
- Service-owned TLS certificates, public listeners, Nginx virtual hosts,
  application upstreams, or trusted-header SSO configuration.
- Rotation, export, capture, or recovery of an existing TOTP secret.

## Decisions

### Use the native NixOS Authelia module with state owned below `/var/lib`

`services.osmium.authelia` will compose the NixOS Authelia package/module rather
than run a container. The module will own a dedicated service account, persistent
state directory, SQLite file, writable managed users database, systemd ordering,
health checks, loopback listener, and optional diagnostic host forwarding.

The native module inherits pinned nixpkgs packaging and repository lifecycle
conventions. A container was rejected because it would add duplicate image,
network, volume, and secret behavior.

### Materialize a writable file backend only at runtime

The file backend will be a deterministic runtime-managed YAML file in persistent
state. The reconciler reads password files, invokes Authelia's supported hash
tooling, atomically writes managed records, and permits the backend's documented
write-back behavior. It records only identity ownership and salted change
fingerprints, not plaintext passwords or hashes in evaluated configuration.

This is selected over a static Nix-generated YAML file because Authelia can
modify the configured user file during supported flows and because hashes derived
from password files must never enter the store. Direct SQLite manipulation is
rejected because it bypasses Authelia's compatibility and encryption boundaries.

### Treat password replacement as validate-then-commit

For a changed password file, reconciliation will stage the derived backend state,
reload or restart Authelia, authenticate using the replacement, and atomically
commit metadata only on success. Failure restores the previous managed file and
keeps the previous fingerprint. A path unit triggers reconciliation for identity
password files and operational secrets.

This keeps changed-secret rotation explicit and preserves known-good access.

### Limit TOTP automation to explicit initial bootstrap

Each user can optionally reference one protected bootstrap input and, if needed,
one protected enrollment output. The reconciler checks the live storage state and
uses Authelia's supported `storage user totp` command family to create or import
a factor only when none exists. The state ledger records only bootstrap
completion. Existing factors, including user-enrolled factors, are never changed
by reconciliation.

Factor replacement and extraction are deliberately excluded: Authelia encrypts
TOTP secrets in storage and rotation would either disrupt the user or require
handling sensitive material without a safe declarative ownership model.

### Expose only generic proxy authorization on loopback

Authelia and its authorization endpoint will listen only on loopback. An external
TLS reverse proxy must provide the documented `X-Forwarded-*` destination and
scheme headers and relay standard authorization responses. The module will set
the trust boundary so a guest-network peer cannot fabricate those headers.

Bundling Nginx or protected routes was rejected because the user selected a
generic endpoint and external proxies own hostname, certificate, routing, and
application header-forwarding policy. The integration test will exercise the
generic endpoint directly from loopback with the required metadata and prove the
raw listener is unreachable through the guest network.

### Keep TLS external but make the contract fail closed

The declared portal URL must be HTTPS and runtime configuration will not accept
an insecure public URL. No certificate or key options will be exposed by the
service. Tests can represent the external TLS hop through loopback forwarded
headers; this validates Authelia's authorization semantics without pretending
the MicroVM owns public TLS.

### Integrate LLDAP as an explicit authentication backend

The module will support a typed LLDAP backend only when the selected LLDAP
service is enabled and its directory endpoint, base DN, search mappings, trust
input, and dedicated bind-password file are valid. Bind credentials are
separate from the LLDAP administrator and Keycloak consumer credentials, and
their changed secret files trigger validated runtime rotation. LDAP mode is an
explicit transition: the retained YAML backend remains available for rollback,
but file-only users are not accepted while LDAP mode is active. Disabling LDAP
mode restores the retained YAML backend without migrating or mutating its
credentials.

### Observe runtime state and make candidates review-only

The reverse tools will combine service facts, generated configuration, the
writable file backend, and supported Authelia storage commands. Their normalized
reports contain provenance, completeness, unsupported-state findings, and
unresolved runtime file references. They never mutate the service or sources and
never serialize passwords, hashes, key files, TOTP values, cookies, or tokens.

## Risks / Trade-offs

- **[Authelia's writable user file conflicts with fully immutable rendering]** →
  Maintain an atomic persistent runtime file and capture unexplained external
  changes rather than silently overwriting them.
- **[External proxy misconfiguration can expose insecure cookies or trust
  spoofed headers]** → Bind only to loopback, require an HTTPS portal URL,
  document required headers, and test direct network denial and valid local
  forwarding.
- **[SQLite does not support multiple active Authelia instances]** → State the
  single-instance limitation in documentation and defer PostgreSQL/Redis HA to a
  separate change.
- **[TOTP CLI behavior may differ across package updates]** → Pin the package,
  use supported CLI operations only, and prove generate/import, no-repeat, and
  second-factor authentication in a MicroVM.
- **[Authelia may change internal storage schema]** → Never write storage
  directly; use supported storage commands and mark unknown state incomplete.

## Migration Plan

1. Deploy a new MicroVM with persistent state, loopback-only Authelia, protected
   storage/session/identity keys, and an HTTPS portal URL representing the
   external proxy URL.
2. Apply user and access-control declarations, then confirm native authentication
   and generic authorization locally before publishing the endpoint.
3. Configure the external TLS proxy separately with the documented forwarded
   headers and retain ownership of every public route and upstream.
4. Add TOTP bootstrap only for users with a deliberate protected input/output
   workflow; verify enrollment before setting two-factor access rules.
5. Roll back by removing the external proxy route or disabling reconciliation
   while retaining persistent state and last-valid runtime inputs. Invalid
   replacements never advance the reconciliation ledger.
