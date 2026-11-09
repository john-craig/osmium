## Purpose

Defines the secure Community Edition boundary for NocoDB identities and prevents licensed-only organization or external authentication settings from being misrepresented as supported.

## ADDED Requirements

### Requirement: Community Edition accepts only local NocoDB identities
The system SHALL use NocoDB-local administrator and user credentials for the Community Edition service. It SHALL reject declarations for native OIDC, SAML, SCIM, Keycloak federation, FreeIPA LDAP federation, externally asserted identity headers, and external identity synchronization because Community Edition cannot provide a native, end-to-end user lifecycle for those features.

#### Scenario: External identity declaration fails closed
- **WHEN** an operator enables Keycloak OIDC, FreeIPA LDAP, SCIM, or trusted-proxy identity for the Community Edition service
- **THEN** evaluation fails before any NocoDB, Keycloak, FreeIPA, or proxy state is changed

### Requirement: Community Edition does not expose organizations or licensed collaboration features
The system SHALL reject declarations and captures for NocoDB organizations, organization roles, teams, team memberships, enterprise record-level security, and other features unavailable to the configured Community Edition. It SHALL identify this state as unsupported rather than silently dropping it or producing a declaration that claims completeness.

#### Scenario: Organization declaration is rejected
- **WHEN** an operator declares an organization or organization-level role for NocoDB Community Edition
- **THEN** evaluation fails with an error that identifies the licensed-only capability

### Requirement: Browser and machine boundaries remain explicit
The system SHALL expose the NocoDB browser UI and machine API at explicit endpoints and SHALL not present a Keycloak gateway as transparent NocoDB sign-on. Documentation and diagnostics SHALL state that a future licensed native SSO integration requires a separate change with its own runtime secrets and live browser login check.

#### Scenario: Gateway bypass is not misrepresented as sign-on
- **WHEN** Community Edition configuration is evaluated with a generic Keycloak browser gateway setting
- **THEN** the setting is rejected and the service retains only its documented local NocoDB login behavior

### Requirement: Community boundary denial is exercised in a MicroVM
The system SHALL expose a `nocodb-community-identity-boundary` flake check that boots NocoDB, authenticates a declared local user, attempts the prohibited external and organization configuration paths, and verifies that no unsupported runtime integration is created.

#### Scenario: Community boundary check executes
- **WHEN** `nix build .#checks.x86_64-linux.nocodb-community-identity-boundary --print-build-logs` runs
- **THEN** it boots a MicroVM and proves local login remains functional while unsupported identity paths are denied
