## ADDED Requirements

### Requirement: Gotify browser access supports optional Keycloak SSO

The service SHALL support an optional Keycloak-authenticated browser endpoint
whose upstream Gotify listener is private to the guest. Enabling browser SSO
MUST retain a separately declared Gotify token endpoint for application and API
clients and MUST NOT convert token requests into interactive redirects.

#### Scenario: Browser SSO is enabled

- **WHEN** a valid Keycloak user completes the configured authorization flow
- **THEN** the user reaches the Gotify browser application through the protected
  endpoint without exposing the private upstream listener

#### Scenario: Notification client uses a token

- **WHEN** a notification client sends a valid application token to the declared
  machine endpoint
- **THEN** Gotify accepts the notification without requiring browser SSO

#### Scenario: Browser SSO is disabled

- **WHEN** no SSO declaration is enabled
- **THEN** existing Gotify networking and authentication behavior remains
  unchanged
