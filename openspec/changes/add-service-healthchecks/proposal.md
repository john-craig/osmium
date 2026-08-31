## Why

Mythoclast currently verifies Gitea startup and behavior, but service tests
define readiness checks ad hoc. A shared healthcheck mechanism will make
service health assertions consistent and allow future MicroVM services to
declare the checks that prove they are reachable and healthy.

## What Changes

- Add a reusable structured HTTP healthcheck helper for MicroVM tests.
- Execute healthchecks inside each service's guest MicroVM.
- Add a Gitea `/api/healthz` check on guest port `3000` expecting HTTP `200`.
- Document the healthcheck contract and verification command.

## Capabilities

### New Capabilities

- `service-healthchecks`: Structured healthchecks executed inside service
  MicroVMs.

### Modified Capabilities

- `gitea-service`: Add an HTTP healthcheck to the existing Gitea integration
  test.

## Impact

- Adds a shared test helper under `tests/`.
- Extends the Gitea MicroVM test without changing the service runtime module.
- Adds no new runtime dependencies or host-side healthcheck behavior.
