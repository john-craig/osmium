## ADDED Requirements

### Requirement: LDAP federation declarations are typed and lifecycle-safe
The system SHALL expose typed per-realm LDAP federation declarations that identify
a declared FreeIPA directory, stable provider identity, supported user and group
mapping settings, runtime bind credential file, and CA trust reference. It SHALL
reconcile only the managed provider instance, persist secret-free ownership and
change-detection metadata, rotate the bind credential after validated live
authentication, and retain the prior working provider state on invalid replacement.

#### Scenario: Managed federation configuration changes
- **WHEN** a declared FreeIPA federation mapping or valid bind credential changes
- **THEN** Keycloak updates only the proven managed provider and continued federated authentication uses the replacement configuration

#### Scenario: Unmanaged federation provider collides
- **WHEN** a declaration matches an existing unmanaged LDAP provider without compatible ownership evidence
- **THEN** reconciliation fails without adopting or changing that provider
