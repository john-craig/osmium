## 1. Secret Integration

- [x] 1.1 Add the pinned `sops-nix` flake input and expose its NixOS module to guest configurations
- [x] 1.2 Verify a Gitea password file can reference `config.sops.secrets.<name>.path` without exposing secret contents during evaluation

## 2. Gitea Bootstrap

- [x] 2.1 Add opt-in administrator username, email, and password-file options
- [x] 2.2 Add the ordered systemd oneshot and persistent completion marker
- [x] 2.3 Ensure failed bootstrap attempts do not create the completion marker and successful bootstrap is not repeated

## 3. MicroVM Verification

- [x] 3.1 Configure a test-only password fixture and bootstrap administrator in the Gitea MicroVM
- [x] 3.2 Verify administrator authentication before and after a guest restart
- [x] 3.3 Verify the persistent completion marker and absence of a second bootstrap attempt

## 4. Documentation And Verification

- [x] 4.1 Document the username, password-file, SOPS wiring, one-time semantics, and non-rotation behavior
- [x] 4.2 Run `nix fmt`, strict OpenSpec validation, and `nix flake check --no-build --no-update-lock-file`
- [x] 4.3 Run `nix build .#checks.x86_64-linux.gitea --print-build-logs` and record the successful MicroVM result
