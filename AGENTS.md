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

## Declarative Attribute Specifications

Whenever an OpenSpec change adds new declarative attributes to any service
module, the specification must include both directions of reverse
configuration for those attributes:

- Drift detection must identify changes to the attributes and provide a
  reviewable conversion into a Mythoclast declaration.
- Live-system capture must read the attributes from a running service/system
  and provide a reviewable conversion into a Mythoclast declaration.

Both mechanisms must remain safe and explicit: they must define their
secret-handling, unsupported or ambiguous state, completeness, provenance, and
non-mutating/review-only behavior. The generated declaration must not claim to
be complete when required state is missing or cannot be represented.

The OpenSpec proposal, design, and task list must identify dedicated MicroVM
integration tests for both drift-based conversion and live-capture conversion.
Each test must boot and exercise the relevant service behavior in a MicroVM;
NixOS option evaluation, system-closure builds, or unit-only tests are not
sufficient. The tests must verify the generated declaration is produced from
the runtime observation/capture rather than from an independently authored
equivalent fixture, and must verify the resulting declaration behavior.

Before considering such a change verified, execute both MicroVM testcases and
report their results. Prefer exposing them as separate flake checks, for
example:

```sh
nix build .#checks.x86_64-linux.<service>-drift-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.<service>-live-capture-reverse-configuration --print-build-logs
```
