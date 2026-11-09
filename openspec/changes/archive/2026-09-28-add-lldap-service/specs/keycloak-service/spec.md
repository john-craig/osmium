## MODIFIED Requirements

### Requirement: Keycloak state and networking are explicit
The system SHALL use a locally managed PostgreSQL database by default, SHALL
persist the complete supported Keycloak and database state across impermanent
guest recreation, and SHALL expose explicit guest and host HTTP or HTTPS
mappings. The externally advertised issuer SHALL remain stable across reboot.
When LLDAP federation or the LLDAP administration gateway is enabled, Keycloak
SHALL validate the declared LLDAP TLS and lifecycle dependency before serving
the dependent path; LLDAP's browser upstream SHALL remain loopback-only.

#### Scenario: Identity state survives guest recreation

- **WHEN** realms and users exist and the MicroVM guest root is recreated
- **THEN** Keycloak returns with the same managed database state, issuer, and
  resource identities

#### Scenario: Public issuer is reachable

- **WHEN** a client resolves the declared issuer through the test or deployment
  network
- **THEN** discovery metadata and authorization endpoints use the declared
  externally reachable scheme, host, port, and path

#### Scenario: LLDAP dependency is unavailable

- **WHEN** enabled LLDAP federation or gateway configuration cannot validate its directory or loopback upstream
- **THEN** Keycloak does not report the dependent integration ready or expose an unauthenticated LLDAP administration path
