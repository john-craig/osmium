# Mythoclast

Reproducible NixOS service definitions running in isolated MicroVMs and
tested with impermanent guest filesystems.

## Status

The project contains a small native NixOS HTTP service and a native Gitea
service. Both are used to verify that declared state survives a reboot while
the guest root filesystem is recreated.

## Design

- Services are native NixOS modules whenever possible.
- Each service is intended to run in its own MicroVM.
- Runtime state must be declared through impermanence.
- Flake inputs and service versions must be pinned.
- Configuration should be safe to evaluate and activate repeatedly.

The examples are exposed as `nixosConfigurations.demo-guest`,
`nixosConfigurations.gitea-guest`, and `nixosConfigurations.demo-host`.

## Gitea

Enable Gitea in a guest with:

```nix
services.mythoclast.gitea = {
  enable = true;
  hostHttpPort = 3001;
  hostSshPort = 2223;
};
```

The module uses SQLite and persists the complete `stateDir` (`/var/lib/gitea`
by default), including repositories, attachments, LFS data, and the database.
External database support and reverse-proxy/TLS configuration are intentionally
left for later changes. Use `databasePasswordFile` for a secret file rather
than putting a password in the Nix configuration.

## Development

Enter the development shell with `direnv`, or run:

```sh
nix develop
```

Evaluate the example guest:

```sh
nix build .#nixosConfigurations.demo-guest.config.system.build.toplevel
```

Run the persistence integration test:

```sh
nix build .#checks.x86_64-linux.persistence
```

Run the Gitea MicroVM integration test:

```sh
nix build .#checks.x86_64-linux.gitea --print-build-logs
```

This test boots Gitea, creates a repository through the HTTP API, restarts the
guest, and verifies the repository remains available and the Gitea state
remains owned by `gitea`.

The test uses a tmpfs root and a separate persistent ext4 volume. It writes
state, reboots the guest, and verifies that the state remains available.

## Next steps

1. Extract common service metadata and MicroVM construction into `lib/`.
2. Add validation for unsupported systems and undeclared mutable paths.
3. Add CI for `nix flake check` and the MicroVM-backed tests.
