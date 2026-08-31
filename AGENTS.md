# Agent Instructions

## New Service Specifications

When proposing an OpenSpec change that adds a new service, always include an
integration testcase that boots and exercises the service in its MicroVM. The
testcase must run the MicroVM, not only evaluate NixOS options or build a
system closure.

The testcase should verify the service's primary behavior and any persistence,
networking, or lifecycle guarantees required by the specification. The
proposal, design, and task list must identify the executable test command and
the behavior it verifies.

When a new service supports administrator or other privileged credentials, the
OpenSpec change must also include a secure, one-time credential bootstrap
workflow whenever the service and deployment model make this practical. The
workflow should consume credentials at runtime, persist its completion state,
avoid repeated creation or rotation, and cover the bootstrap behavior in the
service's MicroVM integration testcase.

When a service supports credential rotation, the OpenSpec change must always
include rotation triggered by a changed secret-file value. The rotation path
must consume the replacement credential at runtime and cover the changed-secret
trigger in the service's integration testcase.

Before considering the change verified, execute the MicroVM testcase and report
its result. Prefer exposing it as a flake check, for example:

```sh
nix build .#checks.x86_64-linux.<service> --print-build-logs
```
