## Why

Osmium needs a reproducible way to run an operational OpenCode server in an
isolated MicroVM while retaining declarative user-level configuration and
keeping provider and server credentials outside the guest image and Nix store.
The service must start unattended, preserve useful OpenCode state, and expose a
testable and secure host-to-guest credential boundary.

## What Changes

- Add a disabled-by-default `services.osmium.opencodeServer` service that creates
  a locked, lingering `opencode` user and configures OpenCode through Home
  Manager.
- Run the OpenCode server as a Home Manager systemd user service without an
  interactive login or graphical session.
- Add declarative server, network, workspace, OpenCode configuration, and
  host-mounted credential inputs with evaluation-time safety checks.
- Mount host credential directories read-only into the MicroVM, consume server
  and provider credentials only at runtime, and fail closed when required
  material is missing or invalid.
- Bootstrap provider authentication once into persistent OpenCode user state and
  rotate it when the mounted secret-file content changes, without placing secret
  values in generated configuration, command arguments, logs, or reverse
  configuration.
- Persist OpenCode session and authentication state independently from mounted
  credentials and workspaces, with safe restart and reboot behavior.
- Add deterministic, review-only drift and live-capture conversion for every
  supported declarative service attribute, including explicit provenance,
  completeness, ambiguity, unsupported-state, and secret-handling metadata.
- Add executable MicroVM integration checks for primary service behavior,
  credential bootstrap and rotation, drift conversion, and live capture.

## Capabilities

### New Capabilities

- `opencode-server-service`: Declarative, Home Manager-managed OpenCode server
  operation inside an Osmium MicroVM, including networking, persistent state,
  host credential mounts, provider authentication lifecycle, workspaces, and
  reverse configuration.

### Modified Capabilities

None.

## Impact

- Adds a Home Manager flake input following the existing nixpkgs input and makes
  its NixOS module available to Osmium guests.
- Adds an Osmium service module, runtime credential/bootstrap tooling,
  persistence declarations, MicroVM shares and port forwarding, and generated
  observation/capture tooling.
- Adds three flake checks:
  `opencode-server`, `opencode-server-drift-reverse-configuration`, and
  `opencode-server-live-capture-reverse-configuration`.
- Uses the nixpkgs OpenCode package and Home Manager's `programs.opencode` and
  `programs.opencode.web` interfaces; production modules for existing services
  remain unchanged.
