## 1. Observed-State Collection

- [x] 1.1 Define the normalized user and organization snapshot schema and verify it excludes credential and volatile fields
- [x] 1.2 Implement paginated read-only Gitea API collection against the pinned package and verify complete multi-page results
- [x] 1.3 Distinguish unavailable, unauthorized, malformed, and incomplete API responses and verify no partial snapshot is accepted

## 2. Drift Classification

- [x] 2.1 Compare normalized observed records with declared users and organizations and verify matching, missing, changed, and unmanaged classifications
- [x] 2.2 Add administrator and organization ownership conflict classification and verify no demotion or transfer recommendation is emitted
- [x] 2.3 Add deterministic JSON and human-readable reports with stable exit codes and verify clean, drift, and operational-error cases

## 3. Operational Integration

- [x] 3.1 Add optional read-only oneshot and timer configuration and verify the workflow does not mutate Gitea records
- [x] 3.2 Persist only sanitized snapshot fingerprints and metadata when enabled and verify repeated identical snapshots remain stable
- [x] 3.3 Document invocation, report schema, classifications, limitations, and secret-handling guarantees

## 4. MicroVM Verification

- [x] 4.1 Extend the Gitea MicroVM test with externally created users and organizations and verify unmanaged detection
- [x] 4.2 Change declared metadata out of band and verify changed-field reporting without correction
- [x] 4.3 Verify reports contain no credentials and that inspection leaves identifiers, ownership, metadata, and database state unchanged
- [x] 4.4 Run `nix fmt`, `openspec validate gitea-drift-detection --strict`, `nix flake check --no-build --no-update-lock-file`, and `nix build .#checks.x86_64-linux.gitea --print-build-logs`
