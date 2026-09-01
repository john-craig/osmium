## 1. Declarative Configuration

- [x] 1.1 Add validated non-admin user options for username, email, profile fields, and runtime password files
- [x] 1.2 Add validated organization options for name, owner reference, description, and visibility
- [x] 1.3 Add evaluation coverage for duplicate identities, unknown owners, invalid visibility, and administrator conflicts

## 2. Identity Reconciliation

- [x] 2.1 Add ordered startup and activation reconciliation after Gitea and administrator bootstrap, verifying missing users and organizations are created
- [x] 2.2 Implement idempotent lookup/create/update behavior and verify repeated reconciliation creates no duplicates
- [x] 2.3 Preserve records removed from configuration and verify no destructive deletion or ownership transfer occurs
- [x] 2.4 Ensure declared users remain non-admin and organization provisioning does not grant administrator privileges

## 3. Credential Handling

- [x] 3.1 Implement per-user runtime password consumption and non-reversible persistent fingerprints without exposing secret contents
- [x] 3.2 Trigger user password rotation from changed secret-file values during activation and verify old-password rejection and new-password authentication
- [x] 3.3 Preserve the last known-good password on failed rotation and verify retry behavior

## 4. MicroVM, Documentation, And Verification

- [x] 4.1 Extend the Gitea MicroVM test with non-admin users, organization ownership/access, visibility, restart persistence, and idempotence
- [x] 4.2 Extend the MicroVM test with changed-secret rotation and failed-rotation recovery
- [x] 4.3 Document declarative user/organization configuration, non-destructive removal, secret handling, and lifecycle behavior
- [x] 4.4 Run `nix fmt`, strict OpenSpec validation, and `nix flake check --no-build --no-update-lock-file`
- [x] 4.5 Run `nix build .#checks.x86_64-linux.gitea --print-build-logs` and report the MicroVM result
