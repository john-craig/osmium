## Context

Each service has its own NixOS MicroVM integration test. Health assertions
should run in that guest so they validate the service's actual guest network
and runtime environment rather than only checking evaluated configuration.

## Decisions

### Use structured test definitions

The shared helper accepts healthcheck attribute sets with a name, guest port,
HTTP path, and expected status. This keeps service-specific test declarations
readable while avoiding duplicated shell and status-parsing logic.

### Execute checks with the NixOS test driver

The helper generates `vm.wait_for_open_port` and `vm.succeed` calls. A check
passes only when an HTTP request from inside the guest returns the exact
configured status code.

### Keep healthchecks test-only initially

This change does not create systemd health services or host monitoring. The
first goal is integration verification; runtime monitoring can build on this
contract later.

## Verification

Run the Gitea MicroVM check:

```sh
nix build .#checks.x86_64-linux.gitea --print-build-logs
```

It must boot Gitea, execute `GET /api/healthz` on guest port `3000`, require
HTTP `200`, and continue through repository creation and persistence checks.
