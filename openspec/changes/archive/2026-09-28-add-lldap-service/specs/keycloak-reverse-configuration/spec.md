## MODIFIED Requirements

### Requirement: Drift conversion covers supported declarative attributes
The system SHALL compare declared and observed Keycloak realms, key-provider
metadata, clients, scopes, roles, groups, users, mappings, non-secret
credential state, supported LLDAP federation metadata, and bounded LLDAP
administration-gateway metadata. It SHALL produce a deterministic, reviewable
Osmium candidate derived from the runtime observation, with field-level
findings, provenance, completeness, unsupported-state reporting, and unresolved
secret-file requirements. Conversion SHALL NOT mutate Keycloak, source files,
ledgers, LLDAP, or running services.

#### Scenario: Runtime state drifts from the declaration

- **WHEN** a supported non-secret client, role, group, user, mapping, key,
  LLDAP federation, or gateway field is changed in the running Keycloak instance
- **THEN** drift conversion reports that exact runtime difference and emits a
  candidate based on the observation rather than an independently authored
  equivalent fixture

#### Scenario: Drift includes secret-backed state

- **WHEN** an observed user, client, administrator, TLS, database, signing-key,
  LLDAP bind, or gateway-cookie resource requires secret material
- **THEN** the candidate contains an unresolved file-reference requirement,
  excludes secret bytes and hashes, and is marked incomplete and not activation
  ready

### Requirement: Live capture covers supported declarative attributes
The system SHALL read supported state from a running Keycloak administrative API
and protocol endpoints and SHALL produce a deterministic declaration candidate
for realms, clients, scopes, roles, groups, users, mappings, public signing-key
metadata, supported LLDAP federation metadata, and bounded LLDAP
administration-gateway metadata. Capture SHALL distinguish local, federated,
unmanaged, unsupported, ambiguous, and secret-backed state and SHALL NOT claim
completeness when required state cannot be represented.

#### Scenario: External realm state is captured

- **WHEN** supported resources are created directly in the running Keycloak
  instance
- **THEN** capture emits their observable non-secret attributes with live-system
  provenance and explicit unresolved inputs

#### Scenario: Unsupported state is encountered

- **WHEN** capture encounters an unsupported identity federation, custom
  provider, unknown protocol mapper, external key storage, unsupported LLDAP
  mapping, or another unsupported resource
- **THEN** it records an actionable finding, omits invented configuration, and
  marks the affected scope incomplete
