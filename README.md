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

Enable one-time administrator bootstrap with a runtime password file:

```nix
sops.secrets.gitea-admin-password = {
  sopsFile = ./secrets.yaml;
  owner = "gitea";
  group = "gitea";
  mode = "0400";
};

services.mythoclast.gitea.admin = {
  enable = true;
  username = "admin";
  passwordFile = config.sops.secrets.gitea-admin-password.path;
};
```

The bootstrap creates the administrator after Gitea starts and records a
completion marker inside `stateDir`. It does not rotate or change the account
on later starts.

Administrator credential rotation can be enabled with a replacement secret:

```nix
services.mythoclast.gitea.admin.rotation = {
  enable = true;
  passwordFile = config.sops.secrets.gitea-admin-rotation-password.path;
  maxAge = 90 * 24 * 60 * 60;
  checkInterval = 60 * 60;
};
```

A changed replacement credential is applied during configuration activation.
The periodic check also rotates credentials after `maxAge` and retries failed
rotations. A failed rotation leaves the current credential usable and does not
record success; disabling rotation does not revert a completed rotation.

Declarative non-admin users and organizations can be provisioned with runtime
password files:

```nix
services.mythoclast.gitea.users.project-user = {
  username = "project-user";
  email = "project-user@example.com";
  passwordFile = config.sops.secrets.gitea-project-user-password.path;
};

services.mythoclast.gitea.organizations.project = {
  name = "project-org";
  owner = "project-user";
  description = "Declarative project organization";
  visibility = "private";
};
```

Users are created without administrator privileges and organizations are
created after their declared owner exists. Reconciliation is idempotent and
updates declared metadata, while removing a declaration does not delete or
transfer an existing Gitea record. Changing a user's secret-file value rotates
that user's password during reconciliation.

### Reverse Configuration Export

Enable the review-only exporter alongside drift detection:

```nix
services.mythoclast.gitea.reverseConfiguration.enable = true;
```

Generate a sanitized drift snapshot first, then export selected records without
changing Gitea or the repository:

```sh
mythoclast-gitea-drift --json --output /tmp/gitea-drift.json
mythoclast-gitea-export --input /tmp/gitea-drift.json \
  --user project-user --organization project-org --output /tmp/gitea-candidate.nix
```

Use `--json` for machine-readable candidates and exclusions. Generated users
contain an unresolved `passwordFile` requirement; fill in a reviewed secret-file
reference manually, evaluate the resulting Nix configuration, review the diff,
and activate it through the normal deployment workflow. Export never adopts
records, edits Nix source, creates adoption markers, activates configuration, or
commits changes. Administrator accounts, unsafe names, duplicate declaration
keys, external identity-provider records, and ambiguous organization owners are
reported as exclusions instead of candidates.

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

This test runs a guest-local HTTP healthcheck against Gitea's
`/api/healthz` endpoint on port `3000`, requiring HTTP `200`. It then creates a
repository through the HTTP API, restarts the guest, and verifies the
repository remains available and the Gitea state remains owned by `gitea`.

Service tests can reuse the structured helper in `tests/healthchecks.nix`:

```nix
healthchecks.http {
  name = "service-http-health";
  port = 8080;
  path = "/healthz";
  expectedStatus = 200;
}
```

The test uses a tmpfs root and a separate persistent ext4 volume. It writes
state, reboots the guest, and verifies that the state remains available.

## Next steps

1. Extract common service metadata and MicroVM construction into `lib/`.
2. Add validation for unsupported systems and undeclared mutable paths.
3. Add CI for `nix flake check` and the MicroVM-backed tests.
