## ADDED Requirements

### Requirement: Keycloak FreeIPA federation dependencies are explicit
When a Keycloak FreeIPA federation is enabled, the system SHALL order Keycloak
after the referenced FreeIPA directory is ready, use only the declared directory
network and CA trust boundary, and revalidate the federation when the bind
credential or trust input changes. A FreeIPA failure or invalid replacement MUST
fail the federation closed without changing Keycloak-local service availability
or weakening Keycloak's HTTPS and issuer behavior.

#### Scenario: FreeIPA dependency becomes unavailable
- **WHEN** the referenced FreeIPA directory is unavailable or its verified LDAPS endpoint cannot be reached
- **THEN** Keycloak retains its local service and local-user behavior while federated authentication is unavailable and diagnosed
