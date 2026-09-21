## Why

Osmium has no native notification service, so applications cannot receive
declaratively managed Gotify endpoints from the same isolated, persistent
MicroVM model used for Gitea. Gotify users and application tokens also need
runtime-safe provisioning because passwords and generated tokens must not enter
Nix evaluation artifacts or the store.

## What Changes

- Add a native NixOS Gotify service module and an optional MicroVM guest
  configuration with explicit HTTP networking and persistent Gotify state.
- Add a secure, one-time Gotify administrator bootstrap workflow that consumes
  its credential from a runtime file and records completion without retaining
  the credential value.
- Add declarative, runtime-reconciled Gotify users with password-file inputs
  and explicit non-administrator identity metadata.
- Add declarative Gotify applications owned by declared users, delivering each
  one-time generated application token through an atomically written,
  protected output file.
- Add stable non-secret managed-state tracking, idempotent reconciliation,
  safe removal, and explicit failure handling for unrecoverable token outputs.
- Add review-only drift conversion and live-system capture for Gotify users and
  applications, with deterministic candidate declarations, provenance,
  completeness, secret redaction, and no implicit adoption or mutation.
- Add MicroVM integration checks for the service, provisioning, bootstrap,
  persistence, runtime notification delivery, and both reverse-configuration
  paths.

## Capabilities

### New Capabilities

- `gotify-service`: Native Gotify deployment, networking, persistence, and
  administrator bootstrap in an Osmium MicroVM.
- `gotify-declarative-identities`: Runtime-safe declarative Gotify user and
  application provisioning, including protected app-token delivery and managed
  lifecycle behavior.
- `gotify-reverse-configuration`: Review-only drift conversion and live capture
  of Gotify user and application declarations.

### Modified Capabilities

- None.

## Impact

- Adds an Osmium service module, Gotify-specific runtime reconciliation tools,
  persistence declarations, documentation, example guest wiring, and flake
  checks.
- Uses the native `services.gotify` NixOS module and the pinned Gotify server
  package; no OCI image or runtime download is introduced.
- Exposes new `services.osmium.gotify` declarative options and protected token
  output paths. Existing service modules and users are unchanged.
