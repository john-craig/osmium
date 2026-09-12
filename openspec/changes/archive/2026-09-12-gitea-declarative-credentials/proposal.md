## Why

The Osmium Gitea module can declaratively create users, organizations, and
repositories, but services still need manually provisioned personal tokens,
SSH deploy keys, and OAuth credentials. Those credentials cannot be reproduced
as fixed Nix values because Gitea generates or accepts runtime key material, but
their intended existence, scope, owner, and delivery path can still be
declared and reconciled safely.

## What Changes

- Add declarative credential definitions keyed by stable local names.
- Support user personal access tokens with declared scopes.
- Support user SSH deploy keys, generating keypairs at runtime when needed and
  registering the public key with Gitea.
- Support OAuth application registration and capability-gated OAuth token
  provisioning. Authorization-code token issuance is explicitly unsupported
  when the installed Gitea API requires interactive user consent.
- Write resulting secret values to explicitly declared output files with
  restrictive ownership, permissions, and persistence behavior.
- Persist only non-secret provisioning metadata so restarts reuse existing
  credentials rather than creating duplicates.
- Revoke credentials and remove managed output material when a declaration is
  explicitly removed, while never revoking unrelated credentials.
- Fail closed for ambiguous owners, unsupported scopes or OAuth flows, missing
  output configuration, unsafe paths, and credentials whose state cannot be
  safely identified.
- Keep secret values out of evaluated configuration, generated store paths,
  persistent metadata, logs, drift reports, and reverse-configuration output.
- Defer automatic credential rotation from the initial version.
- Add drift conversion and live-system capture for credential declarations,
  with explicit incomplete results because secret values cannot be recovered.
- Add separate MicroVM integration checks for provisioning, reuse, revocation,
  output protection, drift conversion, and live capture.

## Capabilities

### New Capabilities

- `gitea-declarative-credentials`: Runtime provisioning, secure delivery,
  lifecycle, drift conversion, and live capture of Gitea credentials.

### Modified Capabilities

- None.

## Impact

- Extends `modules/services/gitea.nix` with credential declarations,
  reconciliation services, runtime state, and secure output handling.
- Extends Gitea observation, drift, and reverse-configuration tooling with
  credential metadata while excluding credential contents.
- Adds runtime dependencies for SSH key generation and OAuth/API operations as
  needed by the supported Gitea version; unsupported OAuth token capabilities
  fail closed without creating fallback credentials.
- Adds MicroVM test fixtures and flake checks exercising a live Gitea service.
- Existing users, organizations, repositories, and administrator credential
  behavior remain unchanged unless a new credential declaration is enabled.
