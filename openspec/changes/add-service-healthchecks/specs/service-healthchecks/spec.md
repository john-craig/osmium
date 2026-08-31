## Purpose

Provides reusable, guest-local healthchecks for service MicroVM integration
tests.

## ADDED Requirements

### Requirement: Services declare structured healthchecks

The system SHALL provide a reusable healthcheck definition with a name, guest
TCP port, HTTP path, and expected HTTP status code.

#### Scenario: HTTP healthcheck is declared

- **WHEN** a service test declares an HTTP healthcheck
- **THEN** the test can generate the corresponding guest-local check without
  duplicating request and status-validation logic

### Requirement: Healthchecks execute inside the MicroVM

The system SHALL execute each declared healthcheck from inside the service's
MicroVM and SHALL wait for its guest port before making the request.

#### Scenario: Healthy service passes

- **WHEN** the service accepts a request on the declared port and returns the
  expected status
- **THEN** the healthcheck succeeds

#### Scenario: Unexpected status fails

- **WHEN** the service returns a status different from the expected status
- **THEN** the MicroVM test fails

### Requirement: Gitea exposes a healthcheck

The Gitea MicroVM test SHALL declare and execute an HTTP healthcheck for
`GET /api/healthz` on guest port `3000` expecting HTTP `200`.

#### Scenario: Gitea healthcheck passes

- **WHEN** Gitea is running and its health endpoint is reachable
- **THEN** the healthcheck returns HTTP `200` and the integration test proceeds
