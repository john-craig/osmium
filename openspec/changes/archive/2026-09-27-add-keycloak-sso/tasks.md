## 1. Native Keycloak Service

- [x] 1.1 Add `modules/services/keycloak.nix`, import it from the module tree,
  and define disabled-by-default typed service, package, issuer, HTTP/HTTPS,
  database, TLS, persistence, and guest/host networking options; verify a valid
  configuration evaluates and invalid issuer, path, TLS, and colliding-port
  declarations fail with actionable assertions
- [x] 1.2 Compose the native NixOS Keycloak and local PostgreSQL modules with
  pinned packages, service ordering, private ownership, readiness, and an
  explicitly test-only insecure HTTP mode; verify the live discovery document
  advertises the declared issuer and production declarations reject insecure
  public transport
- [x] 1.3 Add impermanence declarations for the complete supported Keycloak,
  PostgreSQL, and reconciliation state; verify realm and user state survives
  guest root recreation while runtime credential mounts remain non-persistent
- [x] 1.4 Implement runtime-only administrator bootstrap using protected files
  or systemd credentials, permanent-admin verification, temporary-bootstrap
  cleanup, and a secret-free completion marker; verify exactly one permanent
  administrator authenticates and no password appears in the store, unit
  arguments, journal, or marker
- [x] 1.5 Implement changed-file administrator rotation with prevalidation,
  post-change authentication, and last-valid-state preservation; verify the old
  password fails after a valid replacement and remains usable after an invalid
  replacement without false completion
- [x] 1.6 Implement runtime database and HTTPS credential consumption plus
  changed-file restart/reload behavior; verify replacement TLS material is
  served after rotation and unavailable or invalid inputs prevent readiness
- [x] 1.7 Add example Keycloak guest wiring and flake check `keycloak`; execute
  `nix build .#checks.x86_64-linux.keycloak --print-build-logs` and verify live
  discovery/admin APIs, bootstrap, administrator and HTTPS rotation, PostgreSQL
  persistence, and reboot behavior

## 2. Declarative Realm Model

- [x] 2.1 Define typed realm, client-scope, realm-role, client-role, group, user,
  group/role/user mapping, OIDC client, and removal-policy options with stable
  declaration identities and references; verify valid examples evaluate and
  duplicate, dangling, ambiguous, wildcard-redirect, and unsupported-flow
  declarations fail before activation
- [x] 2.2 Render a non-secret desired-state document containing runtime file
  references and implement a versioned root-owned ledger with atomic
  pending/completed records; verify rendered and persisted artifacts omit all
  test password, client-secret, and private-key bytes and reversible derivatives
- [x] 2.3 Implement ordered, idempotent reconciliation for realms, scopes,
  roles, groups, clients, users, and mappings through supported Keycloak admin
  APIs; verify two runs produce each resource once with the declared attributes,
  claims, and relationships
- [x] 2.4 Implement safe updates and `retain`, `disable`, and `delete` removal
  policies using compatible ledger and live identity proof; verify managed
  resources follow policy, explicit realm deletion is required, unmanaged
  resources remain unchanged, and ambiguous ownership fails closed
- [x] 2.5 Add interruption and retry handling around per-resource ledger state;
  terminate reconciliation at representative mutation boundaries and verify a
  retry completes without duplicates or incorrectly completed records

## 3. Declarative Credentials And Keys

- [x] 3.1 Implement managed user password-file reconciliation with protected
  salted change detection and unsupported/federated-account refusal; verify a
  declared user completes a real OIDC login and a changed file invalidates only
  that user's prior password
- [x] 3.2 Implement confidential-client desired secret files and changed-file
  rotation with post-change client authentication; verify the old secret fails,
  the new secret obtains tokens, unrelated clients remain unchanged, and an
  invalid replacement preserves the prior usable credential
- [x] 3.3 Implement typed realm signing-key providers, private/public pair and
  algorithm validation, priority selection, and public JWKS metadata; verify new
  tokens use the declared key ID and validate against the live JWKS while private
  material remains absent from generated and persisted artifacts
- [x] 3.4 Implement changed-file signing-key rotation by creating a new active
  provider and retaining the old public key for the declared overlap; verify new
  and pre-rotation tokens both validate during overlap, invalid key pairs leave
  the prior signer active, and expired ledger-owned inactive keys can be removed
- [x] 3.5 Add flake check `keycloak-provisioning`; execute `nix build
  .#checks.x86_64-linux.keycloak-provisioning --print-build-logs` and verify all
  supported resource kinds, OIDC claims, idempotence, removal, persistence,
  administrator/user/client/signing-key rotation, overlap, failure preservation,
  and secret exclusion against the running MicroVM

## 4. Reverse Configuration

- [x] 4.1 Implement a normalized read-only observation of supported realm,
  client, scope, role, group, user, mapping, and public key-provider metadata
  with managed status, provenance, unsupported-state findings, and explicit
  secret exclusions; verify API ordering does not change deterministic output
- [x] 4.2 Implement drift comparison and conversion from the actual runtime
  observation into a reviewable Osmium candidate with field findings,
  completeness, activation readiness, and unresolved secret-file references;
  verify conversion does not call mutating endpoints or alter source, ledgers,
  resources, or services
- [x] 4.3 Implement live-system capture and conversion for supported external
  Keycloak state, classifying federation, custom providers/mappers, ambiguous
  identities, and unknown fields as unsupported or incomplete; verify it never
  invents configuration or claims completeness for missing secret-backed state
- [x] 4.4 Add flake check `keycloak-drift-reverse-configuration` that mutates
  supported live state, converts that exact observation, proves secret exclusion
  and non-mutation, and replays represented behavior; execute `nix build
  .#checks.x86_64-linux.keycloak-drift-reverse-configuration
  --print-build-logs`
- [x] 4.5 Add flake check `keycloak-live-capture-reverse-configuration` that
  creates external resources through the live API, captures those exact
  resources, proves provenance, incompleteness, secret exclusion, and
  non-mutation, and replays represented behavior; execute `nix build
  .#checks.x86_64-linux.keycloak-live-capture-reverse-configuration
  --print-build-logs`

## 5. Shared SSO Infrastructure

- [x] 5.1 Define reusable SSO declaration types for stable Keycloak realm/client
  references, issuer, callback, scopes, required claims, client-secret files,
  cookie-secret files, browser ports, and machine ports; verify cross-reference,
  URL, confidential-client, network, and secret-reference mismatches fail
  evaluation
- [x] 5.2 Add a bounded `oauth2-proxy` and nginx browser gateway helper with
  runtime client/cookie secrets, header stripping, issuer/audience/state/nonce
  validation, claim restrictions, private upstream binding, and changed-file
  restart; verify valid replacements are consumed, invalid inputs fail closed,
  spoofed headers are removed, and host/peer upstream bypass fails
- [x] 5.3 Add a reusable real authorization-code test driver that follows live
  Keycloak forms and redirects, preserves cookies/state/nonce, and supports
  positive and denied users without minting fixture tokens; verify it can
  establish a session against a minimal gateway fixture and rejects invalid
  state and authorization responses

## 6. Gitea SSO

- [x] 6.1 Extend `services.osmium.gitea` with opt-in Keycloak SSO options and
  reconcile a native OpenID Connect authentication source from discovery and a
  runtime client-secret file; verify source creation is idempotent, changed
  client secrets rotate, and disabling SSO leaves existing local recovery access
  available
- [x] 6.2 Implement stable subject/username/email matching and required
  group/role policy without automatic administrator elevation; verify an allowed
  Keycloak user creates or matches one non-admin Gitea account and a disabled or
  unauthorized user creates no session or elevated account
- [x] 6.3 Add coordinated flake check `keycloak-sso-gitea`; execute `nix build
  .#checks.x86_64-linux.keycloak-sso-gitea --print-build-logs` and verify real
  Keycloak login, authenticated Gitea behavior, denial, client-secret rotation,
  persistence, and local/machine recovery boundaries across running MicroVMs

## 7. Gotify SSO

- [x] 7.1 Extend `services.osmium.gotify` with opt-in Keycloak browser SSO, a
  loopback-only upstream, separate browser and notification/API ports, and a
  least-privileged managed browser principal/client-token lifecycle; verify SSO
  disabled preserves current networking and enabled mode exposes no raw browser
  upstream
- [x] 7.2 Configure the gateway adapter to inject only the protected managed
  browser credential after successful OIDC authorization while retaining Gotify
  application-token authentication on the machine endpoint; verify an SSO
  session reaches authenticated Gotify behavior, spoofed credentials fail, and
  valid/invalid application tokens continue to succeed/fail without redirects
- [x] 7.3 Add coordinated flake check `keycloak-sso-gotify`; execute `nix build
  .#checks.x86_64-linux.keycloak-sso-gotify --print-build-logs` and verify real
  login, required-claim denial, browser-principal access, upstream-bypass
  rejection, gateway secret rotation, persistence, and notification delivery
  across running MicroVMs

## 8. OpenCode SSO

- [x] 8.1 Extend `services.osmium.opencodeServer` with opt-in Keycloak browser
  SSO, loopback-only OpenCode upstream, separate browser and Basic-auth machine
  endpoints, and gateway runtime secrets; verify existing non-SSO declarations
  retain their current behavior and enabled mode exposes no raw upstream
- [x] 8.2 Configure browser-route Basic credential injection only after valid
  OIDC authorization and preserve caller-supplied Basic authentication on the
  machine route; verify an SSO session reaches a protected OpenCode endpoint,
  denied claims and bypass fail, and current/stale machine credentials
  succeed/fail without redirects
- [x] 8.3 Add coordinated flake check `keycloak-sso-opencode`; execute `nix build
  .#checks.x86_64-linux.keycloak-sso-opencode --print-build-logs` and verify real
  login, denial, browser and automation boundaries, upstream-bypass rejection,
  gateway and OpenCode credential rotation, and persistence across running
  MicroVMs

## 9. Exemptions, Policy, And Documentation

- [x] 9.1 Add an F-Droid boundary assertion to an existing or focused booting
  check and verify a repository client receives index/artifact responses without
  an OIDC redirect; document why interactive SSO is incompatible with this
  protocol
- [x] 9.2 Document that filesystem snapshot tooling has no browser login surface
  and verify its existing command/service checks require no network authentication
  gateway and remain unchanged
- [x] 9.3 Update `AGENTS.md` with mandatory future-service Keycloak SSO
  assessment, native-OIDC-first and bounded-gateway guidance, booting
  Keycloak-to-service login tests when applicable, and documented/tested
  exemptions; verify the instructions explicitly cover OpenSpec proposal,
  design, tasks, implementation, and executable check reporting
- [x] 9.4 Document Keycloak configuration, runtime secret deployment, signing-key
  overlap, resource/removal ownership, recovery, rollback, SSO enablement,
  machine endpoints, Gotify's shared-principal limitation, and all check commands;
  verify examples contain file references rather than secret values and option
  names match evaluated module options

## 10. Final Verification

- [x] 10.1 Run `nix fmt` and verify no formatting changes remain
- [x] 10.2 Run `openspec validate add-keycloak-sso --strict` and verify the
  change passes strict validation
- [x] 10.3 Run `nix flake check --no-build --no-update-lock-file` and verify every
  output, module assertion test, package, and MicroVM check evaluates
- [x] 10.4 Execute and report `nix build .#checks.x86_64-linux.keycloak
  --print-build-logs`, `nix build
  .#checks.x86_64-linux.keycloak-provisioning --print-build-logs`, `nix build
  .#checks.x86_64-linux.keycloak-drift-reverse-configuration
  --print-build-logs`, and `nix build
  .#checks.x86_64-linux.keycloak-live-capture-reverse-configuration
  --print-build-logs`; verify all core and reverse-configuration MicroVM checks
  pass
- [x] 10.5 Execute and report `nix build
  .#checks.x86_64-linux.keycloak-sso-gitea --print-build-logs`, `nix build
  .#checks.x86_64-linux.keycloak-sso-gotify --print-build-logs`, and `nix build
  .#checks.x86_64-linux.keycloak-sso-opencode --print-build-logs`; verify every
  applicable service accepts an allowed Keycloak user, denies an unauthorized
  user, blocks upstream bypass, and preserves its machine-authentication path
