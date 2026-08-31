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

Before considering the change verified, execute the MicroVM testcase and report
its result. Prefer exposing it as a flake check, for example:

```sh
nix build .#checks.x86_64-linux.<service> --print-build-logs
```
