## 1. Native Service And Bootstrap

- [x] 1.1 Add `modules/services/gotify.nix` and module imports with
  `services.osmium.gotify` enablement, state directory, guest/host HTTP ports,
  native `services.gotify` mapping, and evaluation assertions; verify valid
  configurations evaluate and invalid/colliding mappings fail actionably
- [x] 1.2 Add impermanence declarations for the complete Gotify state directory
  and requested persistent application-token outputs; verify generated paths
  survive guest root recreation and undeclared paths do not
- [x] 1.3 Implement the ordered administrator bootstrap unit using runtime
  password-file input and a persisted non-secret completion marker; verify a
  fresh MicroVM authenticates as the bootstrap administrator, a restart does not
  recreate or rotate it, and unavailable input fails without false completion
- [x] 1.4 Add a Gotify example guest configuration and flake check wiring; verify
  `nix build .#checks.x86_64-linux.gotify --print-build-logs` boots the MicroVM,
  exercises authenticated HTTP, and proves state persistence across lifecycle

## 2. Declarative Users And Applications

- [x] 2.1 Define typed `services.osmium.gotify.users` and
  `services.osmium.gotify.applications` options with stable declaration keys,
  identity uniqueness, declared ownership, runtime password-file paths,
  non-admin restrictions, protected output metadata, and safe-area assertions;
  verify invalid declarations fail before activation and evaluated values contain
  no secret contents
- [x] 2.2 Implement runtime user reconciliation through supported Gotify APIs,
  including lookup/create/update and salted protected password-file change
  detection; verify each declared non-admin user exists once and changed file
  content updates only that user's login credential
- [x] 2.3 Implement runtime application reconciliation and one-time token
  delivery for declared user-owned applications; verify app metadata is present,
  the protected output is atomically installed with declared owner/group/mode,
  and the returned token submits a notification to the running Gotify service
- [x] 2.4 Implement the versioned non-secret reconciliation ledger and pending
  creation handling; verify it records only stable identities, remote IDs,
  observable metadata, output metadata, and status, while omitting passwords,
  tokens, and reversible secret digests
- [x] 2.5 Implement restart reuse and lost-output failure handling; verify an
  unchanged restart preserves application ID and token output without duplicates,
  while a missing token output fails closed without creating a replacement
- [x] 2.6 Implement managed application/user removal using compatible ledger
  proof and safe ownership checks; verify removed managed apps lose access and
  outputs, unrelated resources remain usable, and unsafe user deletion reports
  failure without mutation

## 3. Reverse Configuration

- [x] 3.1 Implement sanitized, normalized Gotify observations for users and
  applications with managed status, provenance, unsupported fields, and redacted
  secret presence; verify API order does not change normalized output and no
  password/token value or hash reaches reports or diagnostics
- [x] 3.2 Implement review-only `osmium-gotify-drift` and
  `osmium-gotify-export` conversion with deterministic candidates, explicit
  password-file/token-output requirements, completeness, and field-level drift
  findings; verify adoption, activation, ledger changes, source writes, and
  Gotify mutation are rejected or absent
- [x] 3.3 Implement `osmium-gotify-capture` for running-service users and
  applications, excluding administrators and marking unrecoverable inputs and
  outputs incomplete; verify external resources retain provenance without
  inventing secrets or silently becoming managed
- [x] 3.4 Add flake check `gotify-drift-reverse-configuration` that boots Gotify,
  mutates a declared runtime user/application, converts the exact runtime drift
  observation, consumes the generated candidate's safe metadata behavior, and
  proves non-mutation; execute `nix build
  .#checks.x86_64-linux.gotify-drift-reverse-configuration --print-build-logs`
- [x] 3.5 Add flake check `gotify-live-capture-reverse-configuration` that boots
  Gotify, creates external runtime users/applications, captures and converts the
  exact runtime artifact rather than a fixture, consumes the resulting candidate
  behavior, and proves incompleteness, provenance, secret omission, and
  non-mutation; execute `nix build
  .#checks.x86_64-linux.gotify-live-capture-reverse-configuration
  --print-build-logs`

## 4. Provisioning Integration And Documentation

- [x] 4.1 Add flake check `gotify-provisioning` that boots Gotify, bootstraps its
  administrator, provisions users and applications, verifies application-token
  notification delivery and file protections, restarts, changes a user password
  secret file, removes a declaration, and checks secret omission; execute `nix
  build .#checks.x86_64-linux.gotify-provisioning --print-build-logs`
- [x] 4.2 Document service configuration, persistence, port forwarding,
  one-time administrator bootstrap, user password-file rotation, application
  token outputs, recovery after lost outputs, managed cleanup, and explicitly
  unsupported automatic app-token/admin rotation; verify all documented option
  names match evaluated module options
- [x] 4.3 Document drift and live-capture commands, review-only behavior,
  provenance, completeness, administrator exclusion, secret handling, and the
  operator steps required before activating a candidate; verify examples do not
  include secret values
- [x] 4.4 Run `nix fmt` and verify no formatting changes remain
- [x] 4.5 Run `openspec validate add-gotify-service --strict` and verify the
  change passes strict validation
- [x] 4.6 Run `nix flake check --no-build --no-update-lock-file` and verify all
  outputs evaluate
- [x] 4.7 Execute and report all four Gotify MicroVM checks: `nix build
  .#checks.x86_64-linux.gotify --print-build-logs`, `nix build
  .#checks.x86_64-linux.gotify-provisioning --print-build-logs`, `nix build
  .#checks.x86_64-linux.gotify-drift-reverse-configuration --print-build-logs`,
  and `nix build .#checks.x86_64-linux.gotify-live-capture-reverse-configuration
  --print-build-logs`
