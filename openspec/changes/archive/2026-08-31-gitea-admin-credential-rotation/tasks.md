## 1. Configuration And Secret Handling

- [x] 1.1 Add opt-in rotation options for maximum age, check interval, and replacement password file, with assertions and evaluation tests
- [x] 1.2 Implement runtime-only secret reading and non-reversible persisted credential metadata without exposing plaintext in the store, units, logs, or state

## 2. Expiration And Rotation

- [x] 2.1 Add the ordered rotation oneshot, activation trigger, and periodic timer, verifying changed credentials rotate during activation while unchanged credentials do not
- [x] 2.2 Implement successful rotation and metadata commit semantics, verifying unchanged replacement credentials do not cause redundant changes
- [x] 2.3 Implement failure reporting and retry behavior, verifying missing, unreadable, and rejected replacements preserve the last known-good credential

## 3. Persistence And MicroVM Verification

- [x] 3.1 Persist rotation metadata with the Gitea state and verify it survives guest root recreation
- [x] 3.2 Extend the Gitea MicroVM test with a short deadline, successful rotation, old-password rejection, and post-restart authentication
- [x] 3.3 Extend the MicroVM test with failed-rotation recovery and verify a later valid replacement succeeds without manual account repair

## 4. Documentation And Verification

- [x] 4.1 Document configuration, SOPS wiring, expiration-deadline semantics, failure behavior, retry timing, and rollback expectations
- [x] 4.2 Run `nix fmt`, strict OpenSpec validation, and `nix flake check --no-build --no-update-lock-file`
- [x] 4.3 Run `nix build .#checks.x86_64-linux.gitea --print-build-logs` and report the MicroVM rotation result
