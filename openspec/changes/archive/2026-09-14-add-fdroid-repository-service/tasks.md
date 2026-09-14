## 1. Service Contract And Inputs

- [x] 1.1 Define the `services.osmium.fdroidRepository` option schema for one stable repository identity, metadata, guest port, artifact declarations, and runtime signing-file references; verify valid configurations evaluate and invalid, duplicate, unsafe, and unsupported values fail with actionable errors
- [x] 1.2 Confirm the pinned `fdroidserver` package and required HTTP-serving dependencies are available for `x86_64-linux`; verify package versions and executable interfaces in a Nix evaluation or focused build
- [x] 1.3 Define the repository state layout, generation ledger, readiness marker, permissions, and impermanence declarations; verify evaluated persistence paths contain no secret contents

## 2. Repository Generation And Serving

- [x] 2.1 Implement materialization of declared APK inputs and supported metadata with stable identity and checksum validation; verify exact artifact bytes are preserved and checksum conflicts fail closed
- [x] 2.2 Implement atomic F-Droid metadata and signed-index generation using runtime secret files; verify valid indexes are produced and missing, unreadable, or invalid signing material prevents trusted publication without leaking secrets through argv, environment, closure, or journal
- [x] 2.3 Add the read-only HTTP service and readiness behavior for repository metadata, indexes, icons, and APK files; verify unavailable generation is distinguishable from a ready repository and path traversal is rejected
- [x] 2.4 Add idempotent startup reconciliation and non-destructive declaration removal; verify repeated starts produce equivalent output and do not delete persisted artifacts
- [x] 2.5 Add guest and MicroVM host port configuration with collision assertions and document the stable repository URL; verify evaluation rejects protocol/port conflicts

## 3. Base MicroVM Integration

- [x] 3.1 Add `tests/fdroid-repository.nix` and flake check `fdroid-repository`; verify `nix build .#checks.x86_64-linux.fdroid-repository --print-build-logs` boots the MicroVM and exercises service readiness, repository metadata, signed indexes, APK delivery, and checksum validation
- [x] 3.2 Extend the MicroVM test to reboot the guest and repeat metadata/index/APK probes; verify persisted state restores the same repository identity, index entries, and artifact bytes
- [x] 3.3 Verify the MicroVM test does not commit signing keys or passwords and that service diagnostics and generated artifacts remain secret-free

## 4. Drift Reverse Configuration

- [x] 4.1 Implement normalized runtime drift observation for every supported repository attribute with stable ordering, provenance, and explicit unsupported/ambiguous/completeness findings; verify API/filesystem ordering does not alter the normalized result
- [x] 4.2 Implement deterministic review-only conversion of drift observations into the declarative repository shape; verify additions, removals, metadata changes, artifact checksum conflicts, incomplete observations, and sensitive fields are classified without mutation or secret output
- [x] 4.3 Add dedicated flake check `fdroid-repository-drift-reverse-configuration`; verify `nix build .#checks.x86_64-linux.fdroid-repository-drift-reverse-configuration --print-build-logs` boots the MicroVM, mutates repository state externally, derives the candidate from that runtime observation, and verifies the exact candidate in a separate evaluation/reconciliation path
- [x] 4.4 Verify the drift MicroVM check preserves repository content and identity, produces byte-for-byte repeatable output, and rejects incomplete candidates as not ready for activation

## 5. Live Capture Reverse Configuration

- [x] 5.1 Implement scoped live capture of the running repository with capability facts, provenance, pagination or bounded traversal, stable identity keys, and explicit completeness; verify missing required fields produce incomplete findings
- [x] 5.2 Implement deterministic review-only conversion of live capture output into repository declarations; verify user/runtime ordering cannot change output and signing secrets, private keys, and unsupported content are omitted with explicit findings
- [x] 5.3 Add dedicated flake check `fdroid-repository-live-capture-reverse-configuration`; verify `nix build .#checks.x86_64-linux.fdroid-repository-live-capture-reverse-configuration --print-build-logs` boots the MicroVM, creates or changes runtime repository state, captures it, and feeds the exact generated candidate into a separate evaluation/reconciliation path
- [x] 5.4 Verify the live-capture MicroVM check is non-mutating, repeatable, provenance-aware, and cannot mark missing or ambiguous state complete

## 6. Documentation And Final Verification

- [x] 6.1 Document artifact preparation, supported metadata, signing secret-file requirements, URL and port behavior, persistence, readiness, lifecycle, cleanup boundaries, and reverse-configuration review/activation workflow
- [x] 6.2 Run `nix fmt` and verify formatting leaves no changes
- [x] 6.3 Run `openspec validate add-fdroid-repository-service --strict` and verify the change passes strict validation
- [x] 6.4 Run `nix flake check --no-build --no-update-lock-file` and verify all outputs evaluate
- [x] 6.5 Execute `nix build .#checks.x86_64-linux.fdroid-repository --print-build-logs`, `nix build .#checks.x86_64-linux.fdroid-repository-drift-reverse-configuration --print-build-logs`, and `nix build .#checks.x86_64-linux.fdroid-repository-live-capture-reverse-configuration --print-build-logs`; report each MicroVM result
