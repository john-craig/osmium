## Purpose

Provide a persistent, network-bounded Homebox deployment inside Osmium MicroVMs with native browser OIDC support.

## ADDED Requirements

### Requirement: Homebox service lifecycle
The system SHALL provide a declarative Homebox service using the packaged application and normal Osmium service supervision.

#### Scenario: Service starts in a MicroVM
- **WHEN** a MicroVM is booted with Homebox enabled
- **THEN** Homebox serves its health/status endpoint and browser application through the configured endpoint

### Requirement: Persistent Homebox state
The system SHALL persist the Homebox database and configured attachment/blob storage independently of ephemeral MicroVM state.

#### Scenario: State survives replacement
- **WHEN** a collection, user, and metadata record exist and the MicroVM is replaced while persistent storage is retained
- **THEN** Homebox exposes the same state after the replacement boots

### Requirement: Native OIDC configuration
The system SHALL support Homebox's native OIDC browser flow with client secrets consumed at runtime and SHALL not introduce a separate browser gateway when native OIDC is enabled.

#### Scenario: OIDC boundary is configured
- **WHEN** Homebox is configured with an OIDC issuer, client ID, runtime client secret, and redirect URL
- **THEN** the login flow redirects to the configured identity provider and the client secret is absent from the Nix store and logs

### Requirement: Explicit network boundary
The system SHALL bind Homebox only to its configured listener and SHALL preserve required reverse-proxy and WebSocket behavior without exposing an unintended administrative path.

#### Scenario: Configured endpoint is reachable
- **WHEN** the MicroVM is running behind the configured proxy or listener
- **THEN** browser/API requests and WebSocket upgrades work through that boundary and no additional listener is exposed
