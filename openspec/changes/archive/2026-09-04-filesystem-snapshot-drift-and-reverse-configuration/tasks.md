## 1. Formats And Test Fixtures

- [x] 1.1 Define versioned canonical tree, drift report, snapshot metadata, and reconstruction bundle schemas, and verify representative fixtures validate while unknown versions and malformed records fail
- [x] 1.2 Define byte-safe relative-path encoding, deterministic ordering, supported object metadata, hard-link identity, and excluded filesystem-intrinsic fields, and verify canonical fixtures are stable across repeated generation
- [x] 1.3 Define stable clean, drift, incomplete-export, validation-error, and operational-error exit statuses and reason codes, and verify command-level contract tests cover each outcome

## 2. Snapshot Lifecycle

- [x] 2.1 Add the filesystem snapshot NixOS module with per-subvolume source, snapshot root, schedule, retention, content threshold, exclusions, redactions, and administrative ownership options, and verify valid configurations evaluate and unsafe or non-persistent paths are rejected
- [x] 2.2 Implement serialized initial-baseline, manual-observation, scheduled-observation, and explicit-promotion operations using read-only Btrfs snapshots, and verify unit/integration tests preserve the source and never promote drift implicitly
- [x] 2.3 Implement snapshot identity, source-lineage, read-only, accessibility, and atomic-completion validation, and verify mismatched, writable, missing, and interrupted snapshots fail without producing deletion drift
- [x] 2.4 Implement count- and age-based retention with current-baseline and active-reference protection, and verify only eligible completed snapshots are removed
- [x] 2.5 Declare snapshot metadata and storage through impermanence and verify a MicroVM recreation retains the baseline, eligible observations, and tracker state

## 3. Canonical Filesystem Comparison

- [x] 3.1 Implement non-following, byte-safe traversal for regular files, directories, symlinks, hard links, FIFOs, sockets, and device nodes, and verify symlinks cannot escape the snapshot tree
- [x] 3.2 Implement canonical comparison of types, bytes, link targets, hard-link topology, modes, numeric ownership, mtimes, and extended attributes, and verify fixtures classify additions, removals, content changes, metadata changes, link changes, and type changes
- [x] 3.3 Hash complete contents for every changed regular file and emit reconstructable text or binary-safe content representations within the configured threshold, and verify round-trip reconstruction yields the expected bytes
- [x] 3.4 Emit hashes, sizes, and `content-diff-omitted` without payloads when either file version exceeds the threshold, and verify large metadata-only changes are not misclassified as content drift
- [x] 3.5 Apply exclusion and content-redaction policies before output, and verify exclusions prune traversal while redactions preserve classification and hashes without leaking payload bytes to reports or logs

## 4. Reporting And Operations

- [x] 4.1 Add deterministic JSON and human-readable reports with atomic restricted writes, and verify repeated comparisons are stable and unredacted payloads are accessible only to the configured administrative identity
- [x] 4.2 Add one-shot commands and systemd services/timers for baseline creation, observation, reporting, promotion, and retention, and verify timer failures leave the existing baseline and last complete report intact
- [x] 4.3 Add hash caching keyed only by validated immutable snapshot identity and canonical metadata, and verify cache hits preserve report results while stale or mutable inputs cannot reuse hashes
- [x] 4.4 Document setup, snapshot consistency, scheduling, promotion, retention, exit statuses, performance, path policy, content exposure, and recovery from failed operations, and verify every public module option and command is covered

## 5. Generic Reverse Configuration

- [x] 5.1 Implement deterministic export of a canonical manifest plus content-addressed payloads for creates, replacements, metadata changes, links, and removals, and verify repeated export is byte-for-byte identical
- [x] 5.2 Carry oversized, redacted, unsupported, and ambiguous paths into a machine-readable incomplete list, and verify incomplete bundles cannot pass default deployment validation
- [x] 5.3 Implement whole-bundle preflight validation for schema version, relative path containment, payload hashes, supported object types, completeness, operation ordering, and baseline preconditions, and verify every unsafe case fails before mutation
- [x] 5.4 Implement explicit bundle deployment beneath a configured destination root with deterministic operation ordering and post-application hash checks, and verify a complete fixture reproduces its canonical observed manifest
- [x] 5.5 Add NixOS deployment configuration that selects an external generic bundle path without embedding runtime-generated contents in evaluated configuration, and verify an unselected bundle has no effect and a selected valid bundle runs through its dedicated oneshot unit
- [x] 5.6 Document artifact review, explicit completion of omitted payloads, validation, deployment, non-atomic mode limitations, and rollback, and verify export never edits source, snapshots, Nix files, or version-control state

## 6. Btrfs MicroVM Verification

- [x] 6.1 Add a dedicated test with two separately booted MicroVM nodes and real Btrfs-backed source and snapshot subvolumes, and verify both nodes boot and the first node creates a managed read-only baseline
- [x] 6.2 In the first VM, externally modify a within-threshold file's bytes and supported metadata, capture an observation, and verify the report identifies reconstructable content and metadata drift without modifying either snapshot
- [x] 6.3 Export the first VM's drift and observed canonical manifest to the test-controlled artifact bridge, and verify the bundle is complete, validates successfully, and is the exact input made available to the recreated VM
- [x] 6.4 Start the clean recreated VM from the declared baseline, configure it to consume the runtime-generated bundle, and verify its deployment unit applies the external change successfully
- [x] 6.5 Generate canonical manifests for the first VM's observed tree and the recreated VM's deployed tree and verify they are byte-for-byte identical across paths, types, file bytes, links, permissions, numeric ownership, mtimes, and extended attributes
- [x] 6.6 Extend the MicroVM test with oversized content, redaction, path escape, invalid payload, lineage mismatch, interrupted comparison, retention, and read-only snapshot cases and verify each fails or classifies exactly as specified

## 7. Final Verification

- [x] 7.1 Run `nix fmt` and verify formatting completes without changes remaining from the formatter
- [x] 7.2 Run `openspec validate filesystem-snapshot-drift-and-reverse-configuration --strict` and verify the change passes strict validation
- [x] 7.3 Run `nix flake check --no-build --no-update-lock-file` and verify all flake outputs evaluate
- [x] 7.4 Run `nix build .#checks.x86_64-linux.filesystem-snapshot-drift --print-build-logs` and verify the actual Btrfs MicroVM workflow detects the first VM's external file mutation, exports it, deploys that exact configuration to a recreated VM, and produces identical canonical filesystem state
