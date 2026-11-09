## 1. Native Vaultwarden Service

- [ ] 1.1 Add `modules/services/vaultwarden.nix`, import it from the module tree, and define disabled-by-default typed service, package, URL, bind, guest/host port, state, database, persistence, and runtime-input options; verify valid and invalid declarations with module evaluation tests.
- [ ] 1.2 Compose the native NixOS Vaultwarden service with a dedicated locked user, explicit service ordering, readiness, state/attachment persistence, and read-only runtime credential mounts; verify the service boots in a MicroVM and does not persist credential inputs.
- [ ] 1.3 Add runtime administrator/provisioner credential consumption with protected files, secret-free completion state, changed-input detection, and failure preservation; verify secrets are absent from the store, unit arguments, journal, ledger, and readiness output.
- [ ] 1.4 Record the native Bitwarden authentication and encryption rationale for the Keycloak SSO exemption in module documentation and configuration comments; verify no oauth2-proxy, Keycloak dependency, identity-header injection, or OIDC redirect is generated.
- [ ] 1.5 Add the base `vaultwarden` flake check and execute `nix build .#checks.x86_64-linux.vaultwarden --print-build-logs`; verify live readiness, native client/API behavior, persistence, runtime-input failure, and the no-SSO boundary in a booting MicroVM.

## 2. Declarative User Provisioning

- [ ] 2.1 Define typed stable user declarations for identity, metadata, enabled state, optional master-password file, and supported account policy; verify duplicate, malformed, unsafe-path, and unsupported declarations fail before mutation.
- [ ] 2.2 Implement user provisioning through supported Vaultwarden-compatible API flows with explicit ownership proofs and no personal-vault cipher handling; verify a declared user is created or matched without adopting an unmanaged account.
- [ ] 2.3 Implement optional runtime master-password consumption and secret-free salted change detection; verify omitted passwords remain unresolved rather than generated, and supplied passwords never enter evaluated configuration or persistent artifacts.
- [ ] 2.4 Implement valid master-password rotation with post-change native authentication and invalid-replacement preservation; verify the old password fails only after a successful replacement and unrelated users remain unchanged.
- [ ] 2.5 Add user lifecycle coverage to `vaultwarden-provisioning`; execute the check in a MicroVM and verify user creation, optional credential setup, rotation, restart persistence, and explicit personal-vault provisioning refusal.

## 3. Organization Vault Provisioning

- [ ] 3.1 Define typed organizations, collections, member roles, collection access, and removal-policy declarations referencing stable provisioned-user identities; verify dangling users, duplicate identities, invalid roles, and ambiguous ownership fail evaluation.
- [ ] 3.2 Implement ordered organization, collection, and membership reconciliation with idempotent updates and safe ownership tracking; verify organizations and memberships are created once, role/access changes apply selectively, and unmanaged records remain unchanged.
- [ ] 3.3 Define the pre-encrypted organization-cipher input contract, including stable cipher identity, organization/collection references, required Bitwarden-compatible metadata, protected runtime payload path, and unsupported plaintext inputs; verify malformed or mismatched payloads fail closed.
- [ ] 3.4 Implement organization-cipher create/update/removal through supported APIs without decrypting, generating, logging, hashing for output, or persisting payload bytes; verify a valid encrypted payload is usable by a declared member and invalid replacement preserves the previous cipher.
- [ ] 3.5 Add organization and encrypted-cipher persistence, idempotence, failure, and membership-access coverage to `vaultwarden-provisioning`; execute `nix build .#checks.x86_64-linux.vaultwarden-provisioning --print-build-logs` and verify the running MicroVM behavior.

## 4. Reverse Configuration

- [ ] 4.1 Implement normalized read-only Vaultwarden observation for users, organizations, collections, memberships, credential status, and cipher identities/metadata with provenance, ownership, unsupported-state, and completeness findings; verify API ordering does not alter deterministic output.
- [ ] 4.2 Implement drift comparison and candidate conversion derived from runtime observation, including unresolved master-password and encrypted-cipher input references; verify conversion is review-only, secret-free, and does not mutate resources, ledgers, or services.
- [ ] 4.3 Implement live capture and candidate conversion for externally created Vaultwarden users and organization state; verify personal-vault items, opaque encrypted payloads, unmanaged identities, and unavailable source files are marked unsupported or incomplete rather than invented.
- [ ] 4.4 Add and execute `nix build .#checks.x86_64-linux.vaultwarden-drift-reverse-configuration --print-build-logs`; verify a booting MicroVM mutates exact live non-secret state, derives the candidate from that observation, excludes secrets, proves non-mutation, and replays represented behavior.
- [ ] 4.5 Add and execute `nix build .#checks.x86_64-linux.vaultwarden-live-capture-reverse-configuration --print-build-logs`; verify external resources are created through the live API, captured with provenance, marked incomplete where encrypted inputs are unavailable, and replayed without source mutation.

## 5. Documentation And Integration

- [ ] 5.1 Add `docs/vaultwarden.md` covering module options, native authentication, Keycloak exemption rationale, runtime secret deployment, optional master passwords, pre-encrypted organization ciphers, ownership/removal, recovery, and unsupported states; verify documented option names match evaluated module options.
- [ ] 5.2 Add flake outputs for the base, provisioning, drift, and live-capture MicroVM checks and verify each check boots and exercises Vaultwarden rather than only evaluating a closure.
- [ ] 5.3 Add an explicit boundary assertion to the change artifacts and integration test that Vaultwarden receives no Keycloak gateway, OIDC redirect, spoofable identity headers, or machine-auth bypass; verify native unauthenticated requests fail as expected.
- [ ] 5.4 Run `nix fmt` and verify `git diff --check` reports no formatting or whitespace errors.
- [ ] 5.5 Run `openspec validate add-vaultwarden-service --strict` and verify all proposal, specification, design, and task artifacts pass validation.
- [ ] 5.6 Run `nix flake check --no-build --no-update-lock-file` and verify the Vaultwarden module and all new check derivations evaluate successfully.
- [ ] 5.7 Execute and report `nix build .#checks.x86_64-linux.vaultwarden --print-build-logs`, `nix build .#checks.x86_64-linux.vaultwarden-provisioning --print-build-logs`, `nix build .#checks.x86_64-linux.vaultwarden-drift-reverse-configuration --print-build-logs`, and `nix build .#checks.x86_64-linux.vaultwarden-live-capture-reverse-configuration --print-build-logs`; verify every required MicroVM behavior passes.
