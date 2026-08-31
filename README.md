# Mythoclast

Reproducible NixOS service definitions running in isolated MicroVMs and
tested with impermanent guest filesystems.

## Status

This is the initial foundation. It currently contains a small native NixOS
HTTP service used to verify that declared state survives a reboot while the
guest root filesystem is recreated.

## Design

- Services are native NixOS modules whenever possible.
- Each service is intended to run in its own MicroVM.
- Runtime state must be declared through impermanence.
- Flake inputs and service versions must be pinned.
- Configuration should be safe to evaluate and activate repeatedly.

The current example is exposed as `nixosConfigurations.demo-guest` and a
fully declarative host is exposed as `nixosConfigurations.demo-host`.

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

The test uses a tmpfs root and a separate persistent ext4 volume. It writes
state, reboots the guest, and verifies that the state remains available.

## Next steps

1. Extract common service metadata and MicroVM construction into `lib/`.
2. Add a real native NixOS service with a documented persistence contract.
3. Add validation for port collisions, unsupported systems, and undeclared
   mutable paths.
4. Add CI for `nix flake check` and the MicroVM-backed tests.
