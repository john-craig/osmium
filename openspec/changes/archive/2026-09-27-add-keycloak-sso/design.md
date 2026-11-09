## Context

Osmium composes native NixOS services with impermanence, runtime secret files,
non-secret reconciliation ledgers, and booting MicroVM checks. Gitea already has
runtime reconcilers and protected credential outputs; Gotify and OpenCode expose
service-native credentials but no OpenID Connect login. The pinned nixpkgs has a
native Keycloak module and `oauth2-proxy`, but Keycloak realm import is
create-only and cannot provide ongoing declarative reconciliation or safe secret
rotation. See `proposal.md` and the change specifications for the behavior
contract.

Keycloak and relying services may run in separate MicroVMs. Consequently an SSO
configuration has two independent runtime consumers of each client secret, an
externally stable issuer URL, routable callback URLs, and no safe way to derive
or transfer secret bytes through Nix evaluation.

## Goals / Non-Goals

**Goals:**

- Reconcile a deliberately bounded but useful Keycloak resource model through
  supported administrative APIs after the native service is healthy.
- Make secret file replacement the common rotation trigger while preserving the
  last working credential or key when validation or mutation fails.
- Provide browser SSO without breaking service-native automation, notification,
  health, or repository clients.
- Prove protocol behavior, persistence, rotation, network isolation, reverse
  configuration, and each service login in booted MicroVMs.

**Non-Goals:**

- Arbitrary Keycloak JSON import, the master realm as a user-managed realm,
  identity brokering, LDAP/user federation, custom authenticators, custom
  protocol mappers, external HSM/KMS integration, fine-grained authorization
  services, or every Keycloak extension point.
- Automatic discovery or transfer of secrets between MicroVMs. A deployment
  secret manager must materialize the same desired client secret independently
  for Keycloak and its relying service.
- Replacing Gotify tokens or OpenCode runtime credentials for machine clients.
- Per-Keycloak-user authorization inside Gotify. Its gateway grants a declared
  Keycloak audience a least-privileged managed Gotify browser principal because
  upstream Gotify has no native OIDC identity mapping.
- Interactive SSO in front of F-Droid repository endpoints or command-only
  filesystem snapshot tooling.

## Decisions

### Compose the native Keycloak and PostgreSQL modules

Add `modules/services/keycloak.nix` around `services.keycloak` and local
PostgreSQL, with the complete database and Keycloak state persisted. Use the
pinned nixpkgs package and native systemd service instead of an OCI image.
Expose one stable issuer and explicit guest/host mappings; production
declarations require HTTPS, while a narrowly flagged insecure mode is allowed
only for isolated tests.

Realm files are not the source of truth. Native `realmFiles` imports skip an
existing realm and therefore cannot update declarations or rotate credentials.
The Osmium reconciler owns ongoing configuration.

### Bootstrap through runtime systemd credentials

Do not use `services.keycloak.initialAdminPassword`, which evaluates the secret
into the Nix store. A bootstrap unit reads username and password files through
systemd credential or protected runtime paths, invokes Keycloak's supported
bootstrap/admin commands, verifies administrative login, and records a
versioned completion marker. The temporary bootstrap identity is removed or
disabled after the declared permanent administrator is confirmed.

Subsequent reconciliation compares protected salted file fingerprints and uses
the administrative API to rotate the permanent administrator. It writes the new
fingerprint only after authenticating with the replacement. This follows the
existing Gitea/OpenCode failure behavior: invalid replacement state never
supersedes the last valid state.

### Use a typed desired-state document and ordered runtime reconciler

Render only non-secret desired state and absolute runtime secret references into
a JSON document. A packaged reconciler consumes it after readiness and applies
resources in dependency order: realm, scopes, roles, groups, clients, users,
mappings, credentials, then keys. Stable declaration names and remote UUIDs are
stored in a root-owned versioned ledger. Mutations require both compatible ledger
identity and matching live identity; collisions are errors, not implicit
adoption.

Child-resource removal uses a configurable `retain`, `disable`, or `delete`
policy where supported. Realm deletion defaults to `retain` and requires an
explicit `delete` policy. This is less absolute than deleting every undeclared
object, but avoids destroying unmanaged realm data and makes the declarative
ownership boundary reviewable.

An alternative is generating a full realm JSON file on every activation. It was
rejected because Keycloak startup import is not an update mechanism, secret
values would be difficult to keep out of the store, and partial ownership could
not be distinguished safely.

### Treat password and client-secret files as desired values

Administrator, user, and confidential-client secret files contain the exact
desired credential. The reconciler validates non-empty content, computes only a
salted protected fingerprint for change detection, and sends values over stdin
or a private temporary file to the supported administration command/API. On a
changed fingerprint it updates only the named resource, verifies the new
credential, and commits the fingerprint. Failed verification preserves the
previous completion state.

The same secret must be supplied independently to a relying service. Evaluation
can verify declaration identity and file-reference shape but cannot compare
secret contents without violating the runtime boundary. Each SSO integration
check therefore proves at runtime that both consumers have matching values.

### Rotate realm signing keys with overlap

Model realm keys as managed Keycloak key-provider components. Before mutation,
the reconciler validates the private/public pair, supported algorithm, key ID,
and uniqueness. A changed private-key file creates a new component identity
derived from non-secret public-key metadata, raises its priority for signing,
and changes the prior component to verification-only. The prior public key stays
in JWKS for the configured overlap interval so existing tokens remain valid.
Only an expired, ledger-owned inactive component may be removed.

This staged provider approach is preferred to replacing a provider in place,
which would invalidate outstanding tokens immediately. Private key material is
loaded through a protected runtime file and never copied into the ledger or
observation output; only public certificate/JWK metadata and a one-way local
change detector are retained.

### Use native Gitea OIDC and a bounded gateway for other browsers

Gitea receives a managed authentication source through its supported command or
API, pointing at Keycloak discovery with a runtime client-secret file. Stable
`sub` plus explicitly selected username/email claims control account matching;
automatic administrator elevation is prohibited.

Gotify and OpenCode use the native NixOS `oauth2-proxy` module in front of a
loopback-only upstream, with a minimal nginx routing layer where service-native
credential injection is required. Client and cookie secrets are runtime files.
The gateway restricts issuer, audience, callback, email/group/role claims, and
forwarded headers. It strips caller-supplied identity and authorization headers
before adding its own.

For OpenCode, nginx injects the current runtime Basic credential only on the
browser route; a separate narrowly exposed machine route continues to require
the caller's Basic credential. For Gotify, the gateway uses a dedicated,
least-privileged managed browser principal and injects its protected client
token on proxied service requests. The existing application-token route remains
separate for notification clients. The test must establish that the browser
authorization flow reaches authenticated protected service behavior, not merely
the proxy's success page. This proxy-level Gotify model deliberately does not
claim per-user Gotify identity.

A single generic reverse proxy without service adapters was rejected because it
would authenticate the outer HTTP request but still leave Gotify/OpenCode
credentials unresolved or permit unsafe upstream bypass.

### Keep browser and machine endpoints distinct

SSO mode exposes the gateway as the browser host port and binds the raw upstream
to loopback. Machine endpoints use separate declared ports and firewall rules.
Health probes execute inside the guest or use a narrowly defined health path;
they do not weaken browser authorization. F-Droid remains directly accessible,
because an authorization redirect is not understood by F-Droid clients.

### Share one sanitized observation model

The drift and capture commands normalize supported admin-API responses into a
versioned observation containing non-secret attributes, public key metadata,
managed status, provenance, unsupported state, and explicit exclusions. Drift
compares that observation to the rendered non-secret declaration. Live capture
starts from the observation only. Both emit candidates with unresolved
password, client-secret, private-key, TLS, and database file references and mark
affected candidates incomplete and not activation-ready.

The commands never call endpoints that reveal credentials, never write the
ledger, and never reconcile. Dedicated tests create or mutate actual runtime
resources, derive candidates from those observations, and replay represented
safe behavior in another MicroVM.

### Use separate booting checks for lifecycle, reverse paths, and SSO

Add these flake checks:

- `keycloak`: native startup, discovery, administrator bootstrap/rotation,
  PostgreSQL persistence, HTTPS/runtime-key handling, and reboot.
- `keycloak-provisioning`: all supported realm resources plus user, client, and
  signing-key rotation, token claims, JWKS verification, overlap, removal, and
  secret exclusion.
- `keycloak-drift-reverse-configuration`: live drift, conversion, non-mutation,
  secret exclusion, and replay.
- `keycloak-live-capture-reverse-configuration`: live external resources,
  capture, incompleteness/provenance, non-mutation, and replay.
- `keycloak-sso-gitea`, `keycloak-sso-gotify`, and
  `keycloak-sso-opencode`: a configured Keycloak MicroVM plus the target service
  MicroVM, a real authorization-code flow, positive and denied identity cases,
  callback/session verification, upstream-bypass rejection, and the target's
  machine-auth path.

The SSO driver may automate the browser protocol, cookies, forms, redirects,
PKCE/state/nonce checks, and target assertions without a graphical browser, but
it must interact with the real live endpoints and MUST NOT mint fixture tokens.
Test-only DNS and HTTP allowances remain inside test modules.

### Add a durable repository policy for future services

Update `AGENTS.md` during implementation with a “Keycloak SSO Integration”
section. It requires every future service proposal to assess native OIDC first,
then the bounded gateway, and to include a booting Keycloak-to-service login
check when practical. An exemption must name the incompatible client/protocol or
missing browser surface, preserve the correct machine path, and include a test
of that boundary. This makes SSO applicability part of planning rather than an
afterthought.

## Risks / Trade-offs

- [Keycloak admin API and component schemas vary with the pinned release] -> Pin
  the package through the flake, capability-check endpoints before mutation, and
  fail with versioned actionable diagnostics.
- [A reconciler crash leaves partial desired state] -> Order dependencies,
  persist per-resource pending/completed records atomically, make operations
  idempotent, and test interruption-safe retry behavior.
- [Signing-key rotation can invalidate outstanding tokens] -> Install a new
  provider, retain the previous public verification key for a configured overlap,
  and test both old and new tokens before cleanup.
- [Shared client secrets can diverge across MicroVM mounts] -> Fail readiness on
  OIDC client authentication and exercise changed-secret rotation end to end;
  never attempt secret comparison during Nix evaluation.
- [Proxy SSO can be mistaken for application-native identity] -> Document and
  test the Gotify shared-principal boundary, strip spoofable headers, and avoid
  mapping Keycloak roles to unsupported Gotify authorization.
- [Browser gateway creates an upstream bypass] -> Bind upstreams to loopback,
  expose distinct ports, enforce firewall rules, and test direct connection
  failure from host and peer guests.
- [Large Keycloak scope makes reverse configuration falsely appear complete] ->
  Use a strict supported-field allowlist and mark unknown providers, mappers,
  federation, authentication flows, and secret-backed fields incomplete.
- [End-to-end SSO tests are expensive] -> Keep separate checks for failure
  isolation and cacheable builds; do not replace them with evaluation-only tests.

## Migration Plan

1. Add Keycloak disabled by default, deploy its runtime secrets, boot it, and
   verify the `keycloak` and `keycloak-provisioning` checks before exposing an
   issuer publicly.
2. Declare realms, users, roles, clients, and signing keys. Review generated
   secret paths and removal policies, then reconcile against a fresh realm;
   existing realms remain unmanaged unless identities are explicitly reviewed.
3. Enable Gitea SSO first while retaining local administrator recovery. Verify
   native OIDC login and denied-role behavior before disabling any local user
   login policy.
4. Enable Gotify and OpenCode browser gateways one at a time, leaving their
   machine endpoints and credentials intact. Verify gateway bypass is closed and
   native clients still work.
5. Run and report all seven MicroVM checks named above plus `nix flake check
   --no-build --no-update-lock-file` before considering the change verified.
6. Roll back an SSO integration by removing its gateway declaration and
   restoring the previous host forwarding while retaining Keycloak and local
   recovery credentials. Roll back Keycloak by disabling it only after relying
   services return to local authentication; preserve its database for recovery.
