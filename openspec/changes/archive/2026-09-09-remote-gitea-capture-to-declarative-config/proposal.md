## Why

Mythoclast can already export selected Gitea records after an operator has
collected a local observation, but it cannot safely discover those records from
an existing NixOS host. Operators therefore have to hand-build capture data,
which is slow, difficult to audit, and likely to miss state that must be
represented declaratively. A remote, read-only capture workflow would provide a
reviewable bridge from an existing Gitea installation to Mythoclast while
preserving a path for other Linux distributions later.

## What Changes

- Add a remote capture command that connects to a configured host over SSH and
  collects supported Gitea configuration and live identity state without
  mutating the host.
- Define a versioned, deterministic capture artifact that records source
  identity, probe provenance, supported values, omissions, and safety findings.
- Add a NixOS-oriented remote adapter that discovers the service configuration,
  state paths, runtime user, and API endpoint using read-only probes.
- Add a conversion step that turns a reviewed capture artifact into a
  Mythoclast Gitea declaration candidate, including all supported users,
  organizations, service settings, persistence, and explicit runtime secret-file
  references where known.
- Require unsupported, ambiguous, administrator, external-identity, and
  secret-bearing state to be surfaced as exclusions or completion requirements;
  the workflow must never claim a capture is fully declarative when state is
  omitted.
- Keep capture and conversion review-only: neither operation activates NixOS,
  changes Gitea, writes to the remote host, or edits local source files.
- Define an adapter boundary so future non-NixOS Linux support can reuse the
  capture and conversion formats without changing the generated declaration
  contract.
- Add integration coverage using a remote NixOS test node and the existing
  Gitea MicroVM behavior.

## Capabilities

### New Capabilities

- `remote-gitea-capture`: Read-only remote discovery, deterministic capture
  artifacts, adapter selection, safety classification, and conversion into
  Mythoclast Gitea declaration candidates.

### Modified Capabilities

- None.

## Impact

- Adds a remote capture CLI and a stable capture-artifact schema.
- Extends the existing Gitea reverse-configuration workflow with an input
  produced by remote capture, while preserving its secret-free and review-only
  guarantees.
- Adds SSH client/probe handling and test fixtures; the initial adapter targets
  standard NixOS and Gitea installations only.
- Does not require credentials to be stored in the capture artifact. Remote
  access credentials and optional Gitea API credentials remain operator-managed
  inputs outside generated configuration.
