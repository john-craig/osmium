## Why

Osmium currently has no service for publishing Android applications through the
F-Droid client ecosystem. A native NixOS service would provide a reproducible,
impermanent-friendly repository endpoint that can be recreated inside a
MicroVM, without requiring an external web server or mutable container image.

## What Changes

- Add an `fdroidRepository` service module that serves a configured F-Droid
  repository over HTTP from a dedicated state directory.
- Define declarative repository metadata, signing configuration, and a bounded
  set of APK artifacts or artifact references from which the service generates
  `index-v1.jar`, `index-v2.jar`, and repository metadata.
- Persist generated indexes, downloaded or copied artifacts, signing state, and
  service configuration through the existing impermanence contract.
- Expose configurable guest and MicroVM host HTTP ports with collision checks
  and a health/readiness endpoint or equivalent index probe.
- Support safe runtime secret-file references for signing credentials; secret
  bytes must not appear in evaluated configuration, logs, or generated review
  artifacts.
- Add drift detection and live capture for supported declarative repository
  attributes, each producing deterministic, review-only declaration candidates
  with provenance, completeness, ambiguity, and unsupported-state reporting.
- Add a MicroVM integration test that boots the service, verifies F-Droid client
  metadata and APK delivery, and checks persistence across reboot.
- Add dedicated MicroVM checks for drift reverse configuration and live-capture
  reverse configuration, both using runtime-generated observations rather than
  equivalent hand-authored fixtures.
- Explicitly leave APK compilation, repository administration UI, client
  authentication, multiple repository instances, and arbitrary upload APIs out
  of this initial change.

## Capabilities

### New Capabilities

- `fdroid-repository-service`: Declarative F-Droid repository generation,
  serving, persistence, signing, lifecycle, and reverse configuration.

### Modified Capabilities

None.

## Impact

- Adds a new service module under `modules/services/` and an example MicroVM
  configuration in `flake.nix`.
- Adds F-Droid repository generation and serving dependencies from pinned
  nixpkgs, plus integration tests under `tests/`.
- Adds a stable repository HTTP contract and persisted state layout.
- Requires operators to supply signing material through runtime secret files;
  it does not generate or commit private keys by default.
