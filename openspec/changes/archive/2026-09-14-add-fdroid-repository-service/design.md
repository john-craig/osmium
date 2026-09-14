## Context

Osmium currently provides native NixOS service modules and MicroVM checks, with
impermanence used to retain state across recreation of the guest root. The
existing repository and reverse-configuration patterns require dedicated
MicroVM coverage when a service introduces declarative attributes.

## Goals / Non-Goals

**Goals:**

- Provide one reproducible F-Droid repository instance per guest.
- Generate standard F-Droid repository metadata and signed indexes from
  prebuilt APK inputs.
- Keep signing material runtime-only and preserve repository state through
  impermanence.
- Make HTTP readiness, persistence, and safe lifecycle behavior testable.
- Reuse the repository's deterministic drift and live-capture conventions.

**Non-Goals:**

- Building Android applications or managing source repositories.
- A multi-tenant repository daemon or administration web UI.
- Arbitrary unauthenticated upload endpoints.
- Client authentication, user accounts, or an external database.
- Automatic key generation, key escrow, or private-key migration.
- Full F-Droid metadata coverage beyond the explicitly supported artifact and
  repository fields.

## Decisions

### Use fdroidserver for repository generation

The implementation SHALL use the pinned nixpkgs `fdroidserver` package for
index and metadata generation rather than reimplementing F-Droid formats. This
keeps compatibility with F-Droid clients and delegates signing format details
to the upstream tool. A hand-written index generator was rejected because it
would risk producing subtly invalid or unverifiable indexes.

### Separate generation from serving

A systemd generation unit SHALL materialize a complete repository tree into the
persisted state directory, and a small native HTTP service SHALL serve that
tree read-only. Generation runs before the serving unit is considered ready;
the server never exposes a partially written index. A mutable upload daemon was
rejected because it would expand the trust boundary and make reproducibility
harder.

### Treat APKs as immutable declared inputs

The first contract SHALL accept prebuilt APKs through local store paths or
explicitly supported persisted artifact references, with stable package/version
identity and checksum validation. Artifact bytes are copied or linked into the
persisted repository tree and are never silently replaced when identity and
checksum conflict. APK compilation and remote downloading are deferred because
they introduce separate supply-chain and lifecycle concerns.

### Use runtime secret files for signing

The module SHALL expose paths, not secret values, for the repository signing
key/keystore and its password material. The generation unit reads them only at
runtime with restrictive permissions, uses a temporary private workspace, and
cleans it on exit. The design must account for the exact `fdroidserver` signing
interface during implementation without placing password bytes in unit
arguments or evaluated Nix values.

### Persist the complete generated repository tree

The configured state directory SHALL contain generated indexes, metadata,
icons, APK artifacts, and a small generation ledger. The state directory and
its marker files SHALL be included in the existing impermanence declarations.
Atomic temporary output followed by rename prevents clients from observing a
half-generated index. Rebuilding from declarations remains possible, but
declaration removal is non-destructive by default.

### Implement reverse configuration as review-only tooling

Drift and live capture SHALL observe the generated repository and supported
runtime settings through bounded local commands/files, normalize records by
stable package identity, and render deterministic JSON plus a declaration
candidate. They SHALL report provenance, omitted content, unsupported fields,
missing signing references, and completeness. They must not adopt, activate,
write source files, or expose key material. Dedicated test phases will mutate or
create runtime state, capture it, and feed the exact generated candidate into a
separate evaluation path.

### Test the real service in a MicroVM

Add `tests/fdroid-repository.nix` and a flake check named
`fdroid-repository`. Add separate checks named
`fdroid-repository-drift-reverse-configuration` and
`fdroid-repository-live-capture-reverse-configuration`. The service test guest
will use a deterministic test APK fixture created inside the test workflow,
configure signing material inside the guest, boot the service, fetch and
validate repository metadata/indexes and the APK, and reboot. The two reverse
configuration tests MUST boot and exercise the running service, generate their
inputs from runtime observations, assert secret-free output, and feed the exact
candidate into a separate evaluation/reconciliation path.

## Risks / Trade-offs

- [F-Droid client/index formats or fdroidserver options change] -> Pin the
  nixpkgs input, validate with the actual package, and keep the generated
  repository contract covered by the MicroVM check.
- [Signing material is difficult to pass without leaking through systemd] ->
  Use secret-file paths and runtime reads, avoid environment/argv secrets, and
  test journal and closure output for secret absence.
- [APK metadata is more complex than the initial supported model] -> Reject
  unsupported fields explicitly and record incomplete capture instead of
  inventing metadata.
- [Persisting generated artifacts consumes guest storage] -> Make the artifact
  scope explicit and document that cleanup is an operator-controlled,
  destructive action.
- [Runtime-created repository state cannot be represented declaratively] ->
  Preserve provenance and completeness findings and prevent default readiness
  for incomplete candidates.

## Migration Plan

The service is disabled by default and introduces no migration of existing
repositories. Enable it in a new MicroVM configuration, provide signing files
through the deployment's secret mechanism, and verify the dedicated check. A
rollback consists of disabling the service and removing its MicroVM instance;
the persisted repository directory can be retained for later review or removed
explicitly by the operator.

## Open Questions

None. The initial artifact model, signing boundary, and MicroVM acceptance
behavior are intentionally fixed here; later changes can extend metadata,
upload, or multi-instance support.
