## Why

Gitea currently requires the integration test and operators to create an
administrator manually. A reproducible deployment needs a controlled,
one-time bootstrap path that creates a predefined administrator while keeping
the password outside evaluated Nix configuration and the Nix store.

## What Changes

- Add an opt-in Gitea administrator bootstrap configuration.
- Accept a non-secret administrator username and a password secret-file path.
- Support password files supplied by `sops-nix` through
  `config.sops.secrets.<name>.path`.
- Create the administrator with a persistent, idempotent systemd oneshot.
- Add a MicroVM test that verifies bootstrap, authentication, and no repeat
  creation after restart.
- Document the configuration and SOPS wiring.

## Capabilities

### New Capabilities

- `gitea-admin-bootstrap`: One-time reproducible Gitea administrator creation.

### Modified Capabilities

- `gitea-service`: Add optional administrator bootstrap configuration and
  lifecycle behavior.

## Impact

- Adds `sops-nix` as a flake input and guest module dependency.
- Adds a persistent bootstrap marker beneath the configured Gitea state
  directory.
- Adds a Gitea MicroVM integration assertion for the administrative login.
- Does not rotate, update, or delete the administrator after bootstrap.
