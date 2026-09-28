## MODIFIED Requirements

### Requirement: Realm resources are declaratively configurable
The system SHALL expose typed declarations for realms, enabled state, display
metadata, login policy, client scopes, realm roles, client roles, groups,
group-role mappings, users, user-group mappings, user-role mappings, LLDAP
LDAP federation providers, and bounded LLDAP administration-gateway clients.
Stable declaration keys and remote identifiers SHALL make reconciliation
deterministic and idempotent. Invalid references, duplicate identities,
unsupported settings, ambiguous ownership, unsafe redirects, and directory
collisions MUST fail before mutation.

#### Scenario: A complete realm is reconciled

- **WHEN** a valid realm declaration references roles, groups, users, mappings,
  and an LLDAP federation provider in dependency order
- **THEN** the running realm exposes each resource exactly once with the
  declared non-secret attributes and relationships

#### Scenario: A declaration has an invalid reference

- **WHEN** a mapping or LLDAP integration references an undeclared realm,
  client, role, group, user, directory, or runtime secret input
- **THEN** evaluation fails with the offending declaration path before Keycloak
  is mutated
