## 1. LLDAP Service Foundation

- [ ] 1.1 Add `modules/services/lldap.nix`, import it from the module tree, and compose the native NixOS LLDAP module with disabled-by-default typed LDAP naming, guest/host ports, state, HTTPS UI, and runtime-secret options; verify valid and invalid declarations in module evaluation tests.
- [ ] 1.2 Configure persistent SQLite state, service ownership, loopback-only HTTP/GraphQL binding, declared LDAP/LDAPS listeners, and TLS inputs; verify a booting MicroVM performs authenticated LDAP/LDAPS requests and recreates its guest without data loss.
- [ ] 1.3 Implement one-time administrator bootstrap and explicit changed-file administrator reset policy plus runtime JWT/password-key and TLS secret handling; verify valid rotations are consumed, invalid replacements preserve recovery, and secrets are absent from the store, arguments, journal, readiness output, and ledger.
- [ ] 1.4 Reject unsupported FreeIPA and general-LDAP declarations, including Kerberos, DNS, host enrollment, certificate issuance, HBAC/sudo, replicas, schema management, and write compatibility; verify each unsupported input fails before service mutation.
- [ ] 1.5 Add and execute `nix build .#checks.x86_64-linux.lldap --print-build-logs`; verify a booting MicroVM exercises live LDAP, bootstrap/reset behavior, TLS boundaries, persistence, and secret exclusion.

## 2. Administration Gateway

- [ ] 2.1 Extend the Keycloak and local gateway configuration with typed LLDAP browser route, Keycloak client, callback, operator authorization, and runtime-only client/cookie secret declarations; verify unsafe redirects, public upstreams, missing secrets, and invalid references fail evaluation.
- [ ] 2.2 Implement the bounded LLDAP UI gateway with a loopback-only upstream, HTTPS browser endpoint, Keycloak OIDC state/nonce/PKCE validation, deny-by-default failures, and removal of inbound and generated identity headers; verify the machine GraphQL route remains separate and loopback-only.
- [ ] 2.3 Extend the `lldap` MicroVM check and execute its command; verify authorized Keycloak browser login succeeds, unauthenticated and direct/bypass requests fail, stripped headers cannot authenticate upstream, and LDAP/GraphQL machine paths bypass neither protocol authentication nor the browser gateway.

## 3. Declarative Identities

- [ ] 3.1 Define typed stable LLDAP user and group declarations for supported metadata, enabled state, memberships, password files, and deletion policy; verify duplicate/malformed identities, unsafe paths, dangling memberships, and unsupported attributes fail before mutation.
- [ ] 3.2 Implement root-owned GraphQL reconciliation with a versioned secret-free ownership ledger, ordered user/group/membership updates, and non-adoption of unmanaged records; verify idempotence and ambiguous ownership failures against a running LLDAP instance.
- [ ] 3.3 Implement per-user and consumer bind-password change detection and validation through live LDAP authentication; verify valid replacements reject old credentials, invalid replacements preserve the prior credential, and no secret material enters reports or ledgers.
- [ ] 3.4 Implement removal only for ownership-proven records and retain-by-default behavior for unproven records; verify removal affects only declared managed resources and memberships.
- [ ] 3.5 Add and execute `nix build .#checks.x86_64-linux.lldap-identities --print-build-logs`; verify a booting MicroVM provisions identities, authenticates, rotates credentials, safely removes resources, persists state, and excludes secrets.

## 4. Consumer Integrations

- [ ] 4.1 Extend Keycloak declarations and reconciliation with one ownership-proven LLDAP LDAP federation provider per realm, LDAPS trust validation, supported user/group mappings, dedicated bind-password files, and collision checks; verify local users remain local and unsupported or insecure mappings fail closed.
- [ ] 4.2 Provision separate restricted LLDAP bind users for Keycloak and Authelia, each with independent runtime rotation; verify consumers cannot use the LLDAP administrator credential and rotation does not affect the other consumer.
- [ ] 4.3 Add and execute `nix build .#checks.x86_64-linux.lldap-keycloak-federation --print-build-logs`; verify booting LLDAP and Keycloak MicroVMs perform federated OIDC login and group claims, retain local-login behavior, reject bad TLS, and rotate the bind secret.
- [ ] 4.4 Apply or depend on the completed `add-authelia-service` base module, then add typed LLDAP backend, mapping, trust, and bind-password declarations; verify LDAP mode rejects insecure endpoints, unsafe filters, unavailable LLDAP, and invalid trust.
- [ ] 4.5 Implement Authelia's explicit file-to-LDAP backend transition and rollback without migrating or mutating credentials; verify LLDAP mode denies file-only users and explicit disablement restores the retained file backend.
- [ ] 4.6 Add and execute `nix build .#checks.x86_64-linux.lldap-authelia-ldap-authentication --print-build-logs`; verify booting LLDAP and Authelia MicroVMs exercise LDAP login, group authorization, bind rotation, trust denial, file-only denial, and rollback.

## 5. Reverse Configuration

- [ ] 5.1 Implement normalized read-only LLDAP observation for supported identity, membership, endpoint/TLS, and integration metadata with deterministic ordering, provenance, ownership, completeness, and unsupported-state findings; verify it excludes secrets, password material, hashes, tokens, cookies, and private keys.
- [ ] 5.2 Implement review-only LLDAP drift conversion derived from runtime observations, including unresolved secret references and non-mutating candidate output; verify a MicroVM mutation produces the exact observed change rather than a hand-authored fixture and replay exercises represented behavior.
- [ ] 5.3 Implement LLDAP live capture for externally created supported state and explicit incomplete findings for unavailable or unsupported state; verify capture provenance is live-derived, leaves all sources unmodified, and replay exercises represented behavior.
- [ ] 5.4 Extend Keycloak reverse configuration for supported LLDAP federation and gateway metadata with secret exclusion, provenance, incomplete status, and non-mutation; verify observed LLDAP metadata, not independently authored fixtures, produces the candidate.
- [ ] 5.5 Add and execute `nix build .#checks.x86_64-linux.lldap-drift-reverse-configuration --print-build-logs`; verify a booting MicroVM performs LLDAP drift observation, candidate generation, secret exclusion, non-mutation, and replay.
- [ ] 5.6 Add and execute `nix build .#checks.x86_64-linux.lldap-live-capture-reverse-configuration --print-build-logs`; verify a booting MicroVM captures externally created LLDAP state, records explicit incompleteness, avoids mutation, and replays represented behavior.

## 6. Documentation And Verification

- [ ] 6.1 Add `docs/lldap.md` covering supported LDAP scope, runtime secrets, bootstrap/reset policy, persistence, LDAPS trust, Keycloak/Authelia integrations, Keycloak gateway boundaries, recovery, rollback, and FreeIPA exclusions; verify documented options match evaluated module options.
- [ ] 6.2 Remove or formally mark `add-freeipa-service` superseded in OpenSpec planning and ensure no FreeIPA module/check is enabled by this change; verify only the LLDAP service path is selected for the replacement deployment.
- [ ] 6.3 Run `nix fmt` and `git diff --check`; verify formatting and whitespace checks pass.
- [ ] 6.4 Run `openspec validate add-lldap-service --strict`; verify the proposal, design, five new capability specs, three Keycloak delta specs, and tasks pass strict validation.
- [ ] 6.5 Run `nix flake check --no-build --no-update-lock-file`; verify all LLDAP module, Keycloak, Authelia, gateway, and reverse-check derivations evaluate successfully.
- [ ] 6.6 Execute and report `nix build .#checks.x86_64-linux.lldap --print-build-logs`, `nix build .#checks.x86_64-linux.lldap-identities --print-build-logs`, `nix build .#checks.x86_64-linux.lldap-keycloak-federation --print-build-logs`, `nix build .#checks.x86_64-linux.lldap-authelia-ldap-authentication --print-build-logs`, `nix build .#checks.x86_64-linux.lldap-drift-reverse-configuration --print-build-logs`, and `nix build .#checks.x86_64-linux.lldap-live-capture-reverse-configuration --print-build-logs`; verify every check boots its required MicroVMs and covers service behavior, persistence, networking, lifecycle, credential rotation, browser gateway, integrations, and reverse configuration.
