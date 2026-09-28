## 1. Native Service And Runtime Boundary

- [ ] 1.1 Add `modules/services/authelia.nix`, import it from the module tree, and define disabled-by-default typed package, HTTPS portal URL, loopback listener, diagnostic host port, state path, SQLite, and runtime secret-file options; verify valid and invalid declarations with module evaluation tests.
- [ ] 1.2 Compose the native NixOS Authelia service with a dedicated account, persistent SQLite and writable file-backend paths, explicit unit ordering, atomic runtime configuration, health readiness, and loopback-only binding; verify service startup and guest-network denial in a MicroVM.
- [ ] 1.3 Consume storage-encryption, session, and identity-validation secrets only at runtime with protected environment/configuration files, changed-file restart or reload handling, and failure preservation; verify secret values are absent from the Nix store, unit arguments, journal, state ledger, and readiness output.
- [ ] 1.4 Enforce the external-proxy boundary by requiring an HTTPS portal URL, trusting forwarded metadata only from loopback, and generating no certificate, public virtual host, protected route, Nginx, oauth2-proxy, Keycloak, or OIDC provider configuration; verify evaluation and live network assertions.
- [ ] 1.5 Add the `authelia` flake check and execute `nix build .#checks.x86_64-linux.authelia --print-build-logs`; verify the MicroVM boots, serves live loopback endpoints, persists SQLite state, rejects raw guest-network access, and excludes runtime secrets.

## 2. Declarative Identities And TOTP

- [ ] 2.1 Define typed stable user and group declarations for usernames, enabled state, display name, email, group membership, password files, and optional TOTP bootstrap input/output paths; verify duplicate identities, unsafe paths, malformed metadata, and undeclared group references fail before mutation.
- [ ] 2.2 Implement deterministic runtime YAML user-database rendering and ownership tracking using Authelia-supported password hashing, atomic replacement, and writable-backend preservation; verify declared users authenticate with their metadata/groups without passwords or hashes entering evaluated configuration.
- [ ] 2.3 Implement salted non-reversible password-file change detection and validate-then-commit rotation; verify a changed valid file rejects the previous password, authenticates the replacement, and an invalid replacement leaves the prior credential and ledger state usable.
- [ ] 2.4 Implement optional one-time TOTP creation or import through supported `authelia storage user totp` commands, secret-free completion state, and protected generated enrollment output where configured; verify existing managed and user-enrolled factors are never replaced or exported.
- [ ] 2.5 Add the `authelia-identities` flake check and execute `nix build .#checks.x86_64-linux.authelia-identities --print-build-logs`; verify a booting MicroVM performs user/group provisioning, password rotation, fresh TOTP bootstrap, live second-factor authentication, factor no-repeat behavior, restart persistence, and secret exclusion.

## 3. Generic Proxy Authorization

- [ ] 3.1 Define typed default and ordered access-control rules for supported domains, resources, subjects, groups, and one-factor/two-factor policies; verify unsafe wildcard/domain/path forms, invalid policies, and unresolved groups fail evaluation.
- [ ] 3.2 Render the standard generic Authelia proxy-authorization endpoint configuration for externally managed proxies without creating upstreams, routes, virtual hosts, or trusted-header SSO; verify only standard authorization responses are exposed.
- [ ] 3.3 Add the `authelia-proxy-authorization` flake check and execute `nix build .#checks.x86_64-linux.authelia-proxy-authorization --print-build-logs`; verify a MicroVM request with valid loopback HTTPS forwarded headers redirects when unauthenticated, succeeds when authorized, denies unmatched policy, and cannot be bypassed from the guest network.

## 4. Reverse Configuration

- [ ] 4.1 Implement normalized read-only observation of service facts, managed YAML users, groups, password/TOTP status, TOTP policy, storage mode, and access-control policy with deterministic ordering, provenance, ownership, unsupported-state, and completeness findings; verify it does not export passwords, hashes, keys, TOTP values, URIs, cookies, or tokens.
- [ ] 4.2 Implement drift comparison and review-only candidate conversion derived from runtime observation with field-level differences and unresolved runtime secret-file references; verify commands do not mutate the service, source files, user database, SQLite state, or ledger.
- [ ] 4.3 Implement live capture and candidate conversion for externally created supported user or policy state; verify LDAP, WebAuthn, Duo, external database, unavailable input, user-enrolled factor, and ambiguous state are marked unsupported or incomplete rather than invented.
- [ ] 4.4 Add and execute `nix build .#checks.x86_64-linux.authelia-drift-reverse-configuration --print-build-logs`; verify a booting MicroVM mutates exact live non-secret state, derives a candidate from that observation, excludes secrets, proves non-mutation, and replays represented behavior.
- [ ] 4.5 Add and execute `nix build .#checks.x86_64-linux.authelia-live-capture-reverse-configuration --print-build-logs`; verify a booting MicroVM creates external live resources, captures runtime provenance, marks missing or unsupported state incomplete, proves source non-mutation, and replays represented behavior.

## 5. Documentation And Completion

- [ ] 5.1 Add `docs/authelia.md` covering local users, runtime secret deployment, password rotation, TOTP bootstrap, SQLite single-instance limits, access-control rules, required external TLS/forwarded headers, no-bundled-proxy boundary, recovery, and unsupported capabilities; verify all documented option names match evaluated module options.
- [ ] 5.2 Add flake outputs for the base, identities, proxy authorization, LLDAP authentication, drift, and live-capture checks; verify every named check boots and exercises Authelia in a MicroVM rather than only evaluating a system closure.
- [ ] 5.3 Run `nix fmt` and `git diff --check`; verify formatting and whitespace checks pass.
- [ ] 5.4 Run `openspec validate add-authelia-service --strict`; verify the proposal, design, all four delta specs, and task list pass strict validation.
- [ ] 5.5 Run `nix flake check --no-build --no-update-lock-file`; verify the Authelia module, LLDAP integration, and every new check derivation evaluate successfully.
- [ ] 5.6 Execute and report `nix build .#checks.x86_64-linux.authelia --print-build-logs`, `nix build .#checks.x86_64-linux.authelia-identities --print-build-logs`, `nix build .#checks.x86_64-linux.authelia-proxy-authorization --print-build-logs`, `nix build .#checks.x86_64-linux.lldap-authelia-ldap-authentication --print-build-logs`, `nix build .#checks.x86_64-linux.authelia-drift-reverse-configuration --print-build-logs`, and `nix build .#checks.x86_64-linux.authelia-live-capture-reverse-configuration --print-build-logs`; verify each required lifecycle, authentication, proxy, LLDAP integration, rotation, TOTP, persistence, and reverse-configuration behavior passes in a booting MicroVM.

## 6. LLDAP Integration

- [ ] 6.1 Provision separate restricted LLDAP bind users for Keycloak and Authelia, each with independent runtime rotation; verify consumers cannot use the LLDAP administrator credential and rotation does not affect the other consumer.
- [ ] 6.2 Apply or depend on the completed `add-lldap-service` base module, then add typed LLDAP backend, mapping, trust, and bind-password declarations; verify LDAP mode rejects insecure endpoints, unsafe filters, unavailable LLDAP, and invalid trust.
- [ ] 6.3 Implement Authelia's explicit file-to-LDAP backend transition and rollback without migrating or mutating credentials; verify LLDAP mode denies file-only users and explicit disablement restores the retained file backend.
- [ ] 6.4 Add and execute `nix build .#checks.x86_64-linux.lldap-authelia-ldap-authentication --print-build-logs`; verify booting LLDAP and Authelia MicroVMs exercise LDAP login, group authorization, bind rotation, trust denial, file-only denial, and rollback.
