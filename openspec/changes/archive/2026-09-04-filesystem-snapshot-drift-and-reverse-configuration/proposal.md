## Why

Mythoclast can reconcile and inspect selected application resources, but it
cannot detect arbitrary persisted filesystem changes or turn them into a
reviewable configuration that reproduces the observed state. Btrfs snapshots
provide a filesystem-level observation boundary suitable for detecting drift
without relying on service-specific APIs.

## What Changes

- Add managed creation, retention, and validation of read-only Btrfs snapshots for configured subvolumes.
- Compare a baseline snapshot with a later observed snapshot and classify added, removed, content-modified, metadata-modified, and type-changed paths.
- Require content-aware comparison while allowing full content diffs above a configurable size threshold to be replaced by hashes and an explicit omission reason.
- Add deterministic human-readable and machine-readable drift reports with stable exit behavior and configurable path exclusions and redaction.
- Add a generic reverse-configuration workflow that renders sanitized snapshot changes and required file contents as a reviewable reconstruction candidate.
- Keep observation, export, deployment, and filesystem mutation as distinct operations; export does not edit source files or activate a configuration.
- Add an end-to-end MicroVM test that mutates a first VM, detects and exports its drift, deploys the exported configuration to a recreated VM, and verifies equivalent filesystem state.

## Capabilities

### New Capabilities

- `filesystem-snapshot-drift`: Managed Btrfs snapshot lifecycle and read-only, content-aware filesystem drift detection.
- `filesystem-reverse-configuration`: Generic, sanitized export of detected filesystem changes as a reviewable and deployable reconstruction candidate.

### Modified Capabilities

- None.

## Impact

- Adds a new NixOS module and runtime tooling using the pinned `btrfs-progs` package.
- Adds configuration for tracked subvolumes, snapshot schedules, retention, diff size limits, path policy, reporting, and export.
- Adds persistent snapshot and observation metadata that must be explicitly declared through impermanence.
- Adds a dedicated Btrfs-backed MicroVM flake check exercising snapshot creation, drift detection, export, redeployment, and filesystem equivalence.
- The executable integration check will be `nix build .#checks.x86_64-linux.filesystem-snapshot-drift --print-build-logs` and will verify that a runtime mutation exported from one VM reconstructs identical supported filesystem state in a recreated VM.
- Updates module exports and operational documentation; existing Gitea behavior is unchanged.
