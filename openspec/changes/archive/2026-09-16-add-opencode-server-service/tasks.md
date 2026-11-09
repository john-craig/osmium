## 1. Dependency and Module Foundation

- [x] 1.1 Add an explicit Home Manager flake input that follows `nixpkgs`, import
  its NixOS module into the Osmium guest module stack, and verify
  `nix flake check --no-build --no-update-lock-file` evaluates the existing and
  new outputs.
- [ ] 1.2 Add `modules/services/opencode-server.nix` to the default module imports
  with a disabled-by-default `services.osmium.opencodeServer` option tree for the
  bounded user, Home Manager, network, OpenCode, credential, workspace,
  persistence, and reverse-configuration attributes; verify a module-evaluation
  test accepts valid declarations and rejects unsafe paths, writable credential
  mounts, unauthenticated non-local listeners, overlaps, and port collisions.
- [ ] 1.3 Create the locked `opencode` user and group, private home, stable UID
  support, and lingering user manager, then verify evaluation exposes the
  expected account properties and no login password.

## 2. Home Manager User Service

- [ ] 2.1 Configure `home-manager.users.opencode.programs.opencode` from the
  declared package, settings, TUI settings, and extra packages; verify the Home
  Manager activation package contains the expected user-owned OpenCode files and
  no credential value.
- [ ] 2.2 Configure `programs.opencode.web` as a headless systemd user service
  with declared address, guest port, username, CORS origins, working directory,
  and runtime environment-file path; verify generated unit properties target
  boot-time `default.target`, use the `opencode` identity, and do not depend on a
  graphical login.
- [ ] 2.3 Add user-service ordering, restart policy, and applicable systemd
  hardening around mounts, persistence, and credential reconciliation; verify
  the generated dependency graph prevents readiness before required units and
  mounts succeed.

## 3. Host Mounts, Credentials, and Rotation

- [ ] 3.1 Generate a dedicated read-only `microvm.shares` credential mount and
  separate declared workspace shares using the pinned MicroVM schema; verify
  evaluation preserves each source, target, protocol, and read-only policy and
  rejects unsupported writable or overlapping combinations.
- [ ] 3.2 Implement runtime validation of the server environment file and provider
  authentication JSON, including containment, readability, non-empty values,
  required Basic Auth password, and fail-closed behavior; verify focused tests
  reject missing, malformed, empty, and traversal inputs without starting an
  unauthenticated listener.
- [ ] 3.3 Implement atomic one-time provider-auth bootstrap into the supported
  persistent OpenCode XDG location with a digest-only completion record and
  private ownership/mode; verify repeated reconciliation with unchanged content
  performs no replacement and emits no secret bytes.
- [ ] 3.4 Implement path-triggered and periodic digest reconciliation for changed
  provider authentication and server environment files, atomically preserving
  the last valid provider auth on failure and restarting the user service after
  valid changes; verify focused lifecycle tests cover valid replacement,
  malformed replacement, unchanged input, and distinct digest records.

## 4. Persistence, Health, and Networking

- [ ] 4.1 Persist the supported OpenCode session/data/authentication boundary and
  reconciliation state through Osmium impermanence while excluding credential
  and workspace mounts; verify the evaluated persistence declaration has correct
  paths, ownership, and modes.
- [ ] 4.2 Add guest firewall and MicroVM host-port forwarding for the declared
  endpoint plus collision assertions consistent with existing Osmium services;
  verify module evaluation produces exactly one intended TCP forwarding rule.
- [ ] 4.3 Add an authenticated readiness probe that checks the OpenCode health
  endpoint and usable provider authentication without leaking credentials;
  verify healthy, unauthorized, missing-provider, and listening-but-not-ready
  states are distinguishable.

## 5. Primary MicroVM Integration

- [x] 5.1 Add `tests/opencode-server.nix` and register
  `checks.x86_64-linux.opencode-server`, using runtime-created host credential and
  workspace directories; verify the test boots the MicroVM rather than only
  evaluating options or a closure.
- [x] 5.2 In the primary check, verify boot-time lingering, the Home
  Manager-managed user service, current Basic Auth success, unauthenticated
  rejection, declared CORS, health/version output, and a real OpenCode session
  message routed through a deterministic OpenAI-compatible provider.
- [x] 5.3 In the primary check, verify the credential mount and a read-only
  workspace reject guest writes, an explicitly writable workspace propagates a
  guest-created file to the host with expected ownership behavior, and credential
  bytes remain unchanged.
- [x] 5.4 In the primary check, create supported session state, reboot the
  impermanent guest, and verify session/auth state survives, undeclared root
  state disappears, and unchanged provider bootstrap does not repeat.
- [x] 5.5 In the primary check, replace the provider auth file and server
  environment file from the host and verify automatic digest-triggered rotation,
  service restart, use of the new provider credential, rejection of the old HTTP
  password, acceptance of the new password, and preservation of last valid auth
  after a malformed replacement.
- [x] 5.6 In the primary check, scan generated files, command lines, health output,
  journals, diagnostics, and reverse outputs for all fixture secrets, then run
  `nix build .#checks.x86_64-linux.opencode-server --print-build-logs` and record
  a passing result.

## 6. Drift Reverse Configuration

- [ ] 6.1 Implement secret-free runtime observation and drift comparison for every
  supported declarative attribute using account, user-unit, process, listener,
  mount, workspace, persistence, generated configuration, digest-record, and
  health facts; verify deterministic fixtures cover changed, missing, ambiguous,
  unsupported, host-only, and secret fields.
- [ ] 6.2 Implement deterministic Nix-shaped drift candidates with provenance,
  scope, completeness, exclusions, and activation-blocking unresolved inputs,
  ensuring the command writes only to stdout or an explicit output path; verify
  it does not mutate the service, Home Manager generation, credentials,
  persistence, source, or VCS state.
- [x] 6.3 Add and register
  `checks.x86_64-linux.opencode-server-drift-reverse-configuration`; boot the
  MicroVM, introduce observable supported drift, prove the candidate derives from
  that mutation, supply unresolved host/secret inputs, and verify the resulting
  declaration's behavior in a MicroVM.
- [x] 6.4 Run
  `nix build .#checks.x86_64-linux.opencode-server-drift-reverse-configuration --print-build-logs`
  and record that runtime-derived conversion, secret omission, explicit
  incompleteness, non-mutation, and resulting declaration behavior all pass.

## 7. Live-Capture Reverse Configuration

- [ ] 7.1 Implement runtime live capture for every supported declarative
  attribute with stable ordering, provenance, scope, completeness, secret
  exclusions, ambiguity, unsupported-state handling, and unresolved host-source
  placeholders; verify repeated unchanged captures are byte-for-byte identical
  apart from documented volatile metadata.
- [x] 7.2 Add and register
  `checks.x86_64-linux.opencode-server-live-capture-reverse-configuration`; boot
  the MicroVM, create runtime OpenCode state, prove capture uses observed service
  facts rather than an equivalent authored fixture, supply unresolved inputs,
  and verify the resulting declaration's behavior in a MicroVM.
- [x] 7.3 Run
  `nix build .#checks.x86_64-linux.opencode-server-live-capture-reverse-configuration --print-build-logs`
  and record that deterministic runtime capture, secret omission, explicit
  incompleteness, non-mutation, and resulting declaration behavior all pass.

## 8. Documentation and Final Verification

- [ ] 8.1 Document a complete host and guest example using host-side `sops-nix`
  materialization, private runtime directory permissions, read-only credential
  sharing, explicit writable workspace opt-in, host-port exposure, authenticated
  health checks, rotation behavior, and rollback; verify all documented option
  names and commands evaluate against the module.
- [x] 8.2 Run `nix fmt`, `git diff --check`,
  `nix flake check --no-build --no-update-lock-file`, and
  `openspec validate add-opencode-server-service --strict`, fixing all failures
  and recording passing results.
- [x] 8.3 Re-run all three required executable checks with `--print-build-logs`
  after final changes and record their passing results before considering the
  implementation complete.
