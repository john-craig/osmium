## Why

The current Gitea administrator bootstrap is intentionally one-time and does
not provide a controlled way to replace credentials. Long-lived administrator
passwords increase operational and security risk, while an unsafe automated
rotation could lock operators out of the service.

## What Changes

- Add a configurable administrator credential rotation policy with an explicit
  maximum credential age and check interval.
- Trigger rotation during configuration activation when the replacement secret
  differs from the last successfully applied credential.
- Consume replacement credentials from a runtime secret file, compatible with
  `sops-nix`, without embedding secret contents in evaluated configuration or
  the Nix store.
- Track only rotation metadata and a non-reversible secret identity in the
  persisted Gitea state directory.
- Rotate the administrator only when a replacement secret is available and
  the configured expiration deadline has been reached.
- Preserve the current credential if rotation fails, retry later, and expose a
  clear failure status without disabling the administrator prematurely.
- Extend the Gitea MicroVM test to verify successful rotation, persistence,
  stale-credential rejection, and safe recovery from an unavailable
  replacement secret.
- Document the expiration, rotation, failure, and recovery semantics.

## Capabilities

### New Capabilities

- `gitea-admin-credential-rotation`: Expiration policy and safe administrator
  credential rotation.

### Modified Capabilities

- None. The existing one-time bootstrap contract remains unchanged when
  rotation is disabled.

## Impact

- Extends `modules/services/gitea.nix` with rotation options and persistent
  systemd scheduling/state.
- Extends `tests/gitea.nix` with end-to-end MicroVM rotation scenarios.
- Updates README configuration and operational guidance.
- Does not add a new external dependency; it reuses the existing runtime
  secret-file and Gitea administrator mechanisms.
