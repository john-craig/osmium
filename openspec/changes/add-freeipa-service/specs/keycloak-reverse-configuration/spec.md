## ADDED Requirements

### Requirement: FreeIPA federation metadata is observed and converted safely
The system SHALL include supported Keycloak FreeIPA LDAP federation metadata in
drift and live-capture observations, including provider identity, directory
reference, endpoint, base DN, mapping subset, and CA trust reference. Candidates
SHALL derive from runtime observation, mark bind credential paths unresolved,
remain incomplete until reviewed, and SHALL NOT export bind secrets, directory
passwords, TLS private keys, or federated user credentials.

#### Scenario: Federated provider drift is converted
- **WHEN** supported non-secret FreeIPA federation metadata changes in the running Keycloak realm
- **THEN** the generated review-only candidate reports that observed provider difference without mutating Keycloak or FreeIPA
