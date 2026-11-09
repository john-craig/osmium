## 1. Service Foundation

- [ ] 1.1 Add `modules/services/paperless.nix` and import it from `modules/default.nix`, composing the native `services.paperless` module and `pkgs.paperless-ngx`; verify disabled evaluation is unchanged and enabled evaluation succeeds.
- [ ] 1.2 Define Osmium options for state/data/media/consume/export paths, guest/host HTTP ports, health endpoint, resource settings, native Paperless settings, environment files, and explicit persistence; verify unsafe paths, port collisions, and incompatible directory ownership fail evaluation.
- [ ] 1.3 Configure persistent ownership for Paperless data, media, consumption, export, search index, SQLite state, and optional broker state; verify a consumed document, search index, and user state survive service restart and impermanent guest-root recreation.
- [ ] 1.4 Wire runtime-only secret key, administrator password, database/broker credentials, and other environment-file inputs with explicit systemd ordering; verify secrets are absent from Nix store paths, generated configuration, process arguments, logs, and ledgers.
- [ ] 1.5 Add readiness and health checks, optional PostgreSQL/broker dependencies, and explicit MicroVM forwarding/firewall behavior; verify the running service reaches its health endpoint and rejects undeclared network access.
- [ ] 1.6 Add the `paperless` flake check and execute `nix build .#checks.x86_64-linux.paperless --print-build-logs`; verify a booting MicroVM consumes/searches a fixture document, persists data, starts with runtime secrets, and recreates its guest root safely.

## 2. Users, Groups, Permissions, And Tokens

- [ ] 2.1 Define typed user declarations for stable username/email, display metadata, active/staff/superuser state, runtime password file, group memberships, supported permissions, and explicit removal policy; verify duplicate identities, unsafe paths, dangling groups/permissions, bootstrap collisions, and unsafe privilege transitions fail evaluation.
- [ ] 2.2 Implement ownership-safe group/user/permission reconciliation through versioned Paperless REST APIs; verify managed creation/update/password rotation, unmanaged-user preservation, idempotent restart, and explicit safe removal against the live service.
- [ ] 2.3 Define typed per-user API-token declarations with stable names, required user references, protected output path/owner/group/mode/persistence metadata, rotation trigger, and removal policy; reject independent token scopes and verify unsafe output paths or duplicate user-token identities fail before mutation.
- [ ] 2.4 Implement a pinned Paperless token adapter using `/api/token/` where sufficient and `paperless-manage`/Django token operations only where required for token replacement; verify adapter/package compatibility before mutation and ensure unmanaged tokens are never adopted.
- [ ] 2.5 Implement atomic token output delivery, salted fingerprint/ownership ledger entries, live authorization probes, changed-trigger replacement, failed-replacement retention, and managed token cleanup; verify token values never occur in Nix output, logs, reports, candidates, or ledgers.
- [ ] 2.6 Add the `paperless-identities` flake check and execute `nix build .#checks.x86_64-linux.paperless-identities --print-build-logs`; verify a booting MicroVM provisions users/groups, tests permission-allowed and permission-denied API operations, uses per-user tokens, rotates a token, preserves unmanaged identities/tokens, and protects outputs.

## 3. Reverse Configuration

- [ ] 3.1 Implement `osmium-paperless-observe` for deterministic local-user, group, permission, managed-token metadata/presence, ownership, API-version, provenance, and completeness observation without mutating Paperless, documents, source files, runtime secrets, or the ledger.
- [ ] 3.2 Implement drift comparison and review-only candidate conversion with unresolved password-file/token-output requirements, secret exclusion, unsupported-field findings, and explicit incomplete/not-ready status; verify candidates derive from observation rather than authored equivalent fixtures.
- [ ] 3.3 Add `paperless-drift-reverse-configuration` and execute `nix build .#checks.x86_64-linux.paperless-drift-reverse-configuration --print-build-logs`; verify a booting source MicroVM changes managed identity state, derives a candidate from live observation, proves non-mutation, and validates replay or exact blockers.
- [ ] 3.4 Add `paperless-live-capture-reverse-configuration` and execute `nix build .#checks.x86_64-linux.paperless-live-capture-reverse-configuration --print-build-logs`; verify a booting source MicroVM creates external users/token metadata, captures runtime-derived state, excludes secrets, proves source safety, and validates replay or explicit incompleteness.

## 4. Documentation And Final Verification

- [ ] 4.1 Add `docs/paperless.md` covering package/module provenance, persistent paths, SQLite/PostgreSQL/broker choices, runtime secrets, document consumption, local users/groups/permissions, one-token-per-user semantics, no-scope limitation, token rotation/output recovery, native OIDC assessment, migration, rollback, and reverse-configuration limits; verify documented options and check commands match the implementation.
- [ ] 4.2 Add the Paperless guest configuration and all four MicroVM checks to `flake.nix`; verify `nix flake check --no-build --no-update-lock-file` evaluates the module and check derivations.
- [ ] 4.3 Run `openspec validate add-paperless-service --strict` and `git diff --check`; verify all artifacts are structurally valid and whitespace-clean.
- [ ] 4.4 Execute and report `nix build .#checks.x86_64-linux.paperless --print-build-logs`, `nix build .#checks.x86_64-linux.paperless-identities --print-build-logs`, `nix build .#checks.x86_64-linux.paperless-drift-reverse-configuration --print-build-logs`, and `nix build .#checks.x86_64-linux.paperless-live-capture-reverse-configuration --print-build-logs`; verify every named check boots a MicroVM and exercises the required Paperless lifecycle, identity, token, persistence, and reverse-configuration behavior.
