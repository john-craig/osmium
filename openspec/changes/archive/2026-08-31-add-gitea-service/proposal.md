## Why

Mythoclast currently has only a test service, so it does not yet validate the
service-definition model against a stateful, production-relevant application.
Gitea is a good first service because it exercises persistent repositories,
configuration, HTTP, and SSH while remaining available as a native NixOS
service.

## What Changes

- Add a native Gitea service definition to Mythoclast.
- Run Gitea in its own declarative MicroVM instance.
- Declare Gitea's state, repository, attachment, LFS, and database data through
  impermanence.
- Expose configurable HTTP and SSH guest ports with deterministic host
  forwarding.
- Add a MicroVM integration test covering startup, HTTP health, repository
  creation, and persistence across reboot.
- Document the Gitea configuration and persistence contract.

## Capabilities

### New Capabilities

- `gitea-service`: Native Gitea service configuration, networking, persistence,
  and MicroVM lifecycle behavior.

### Modified Capabilities

None.

## Impact

- Adds `services.gitea` integration through a new Mythoclast service module.
- Adds Gitea-specific persistence declarations and stable service identity.
- Extends the flake's example configurations and NixOS checks.
- Uses the existing `impermanence` and `microvm.nix` inputs; no OCI image or
  runtime download is introduced.
