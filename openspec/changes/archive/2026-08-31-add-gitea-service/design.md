## Context

The current project exposes a default guest module, a host module, and a
single native test service. The guest uses impermanence with a separate
`/persistent` filesystem, while MicroVM host configuration is declarative.
The existing module does not yet provide a generic service-instance registry,
so Gitea will establish the first real service-specific integration pattern.

## Goals / Non-Goals

**Goals:**

- Add one deterministic Gitea guest configuration.
- Keep Gitea native to NixOS and avoid OCI image mutability.
- Declare all Gitea data paths through impermanence.
- Test application behavior across a guest reboot.
- Make HTTP and SSH exposure explicit and validate collisions during evaluation.

**Non-Goals:**

- Supporting multiple Gitea instances in the first implementation.
- Configuring an external PostgreSQL or MySQL cluster.
- Providing reverse-proxy or TLS automation.
- Migrating existing Gitea data.
- Creating a general service registry beyond what Gitea needs.

## Decisions

### Use the native NixOS Gitea module

The service SHALL be built from `services.gitea`, using its declarative
settings, `stateDir`, database options, and secret-file options. This keeps
the closure reproducible and avoids pulling mutable images at runtime.

An OCI definition was considered but rejected for this first service because
image digest management and container persistence would obscure the behavior
being tested.

### Use SQLite for the first instance

The initial instance SHALL use SQLite stored under the persisted Gitea state
directory. This keeps the first integration test self-contained. External
database support can be added later without changing the service's HTTP/SSH or
persistence contract.

### Persist the complete Gitea state directory

The service SHALL persist the configured `services.gitea.stateDir`, including
repositories, attachments, packages, LFS data, and generated application data.
The implementation should avoid maintaining a manually curated list of
subdirectories until a real need to separate backup classes appears.

### Use separate guest and host ports

Gitea SHALL listen on stable guest ports, with explicit host forwarding in the
MicroVM definition. The module SHALL assert that host port/protocol pairs do
not collide. SSH's externally visible port SHALL also be reflected in
`services.gitea.settings.server.SSH_PORT`.

### Test through the Gitea HTTP API

The test SHALL use the local HTTP API to verify readiness and create a
repository, then reboot and verify the repository remains present. Credentials
for the test may be generated only inside the test guest and SHALL not be
committed or embedded in the flake.

## Risks / Trade-offs

- [Gitea option names or defaults change across nixpkgs revisions] -> Pin the
  flake lock file and evaluate the generated configuration in CI.
- [Persisting the complete state directory retains unnecessary cache data] ->
  Treat this as the safe initial default and split paths only after measuring
  backup or startup impact.
- [SQLite is unsuitable for high-concurrency production use] -> Document it as
  the initial single-instance default and add external database support as a
  separate change.
- [MicroVM port forwarding differs between local and CI environments] -> Keep
  the integration test guest-local and separately validate the declarative host
  port mapping during evaluation.

## Migration Plan

There is no existing Gitea deployment to migrate. Add the service disabled by
default, enable it in the example guest, run the persistence test, and then
document the configuration. Rollback consists of disabling the service and
removing the generated MicroVM instance; no existing state is modified.

## Open Questions

None for this change. External database support, reverse proxy integration, and
multi-instance support are intentionally deferred to later proposals.
