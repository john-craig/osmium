# gitea-reverse-configuration Specification

## Purpose

Provides a safe, reviewable way to render observed Gitea identities as
declarative configuration candidates without treating live state as approved
desired state or exposing credentials.

## Requirements

### Requirement: Observed identities can be exported as configuration candidates

The system SHALL render selected observed users and organizations into a
deterministic, Nix-shaped candidate configuration. The candidate SHALL preserve
stable Gitea usernames and organization names and SHALL use stable local
declaration keys that do not depend on output ordering.

#### Scenario: Export an unmanaged user

- **WHEN** an operator selects an unmanaged non-administrator user for export
- **THEN** the output contains a declaration with the observed username and supported profile fields

#### Scenario: Export an organization with a known owner

- **WHEN** an operator selects an organization whose owner is an unambiguous observed user
- **THEN** the output contains the organization name, supported metadata, and owner reference

#### Scenario: Export order changes

- **WHEN** the same observed state is returned in a different API order
- **THEN** the generated configuration is byte-for-byte deterministic apart from explicitly documented timestamps or headers

### Requirement: Generated configuration is secret-free

The system SHALL NOT emit passwords, password hashes, access tokens, SSH keys,
session credentials, or secret contents. It SHALL NOT invent a secret path. A
generated user declaration SHALL identify that a password file must be supplied
manually or use an explicit unresolved placeholder that prevents accidental
activation.

#### Scenario: User has no known secret path

- **WHEN** a user is exported from observed Gitea state
- **THEN** the output requires the operator to provide a password-file reference and contains no password value

#### Scenario: Sensitive observed fields are present

- **WHEN** the source snapshot includes credential-related fields
- **THEN** those fields are omitted from every output format and diagnostic

### Requirement: Unsafe records require explicit handling

The system SHALL refuse or exclude administrator accounts, ambiguous identity
matches, unsafe names, external-identity-provider accounts, and organizations
with unresolved or conflicting owners from an adoptable candidate. Each excluded
record SHALL have a machine-readable reason and a human-readable explanation.

#### Scenario: Administrator is selected

- **WHEN** an operator selects an administrator account for export
- **THEN** the system excludes it from adoptable configuration and reports the administrator safety conflict

#### Scenario: Organization owner is ambiguous

- **WHEN** an organization cannot be mapped to exactly one safe user declaration
- **THEN** the system excludes the organization from adoptable configuration and reports the ownership ambiguity

#### Scenario: Unsafe identity name is selected

- **WHEN** a selected username or organization name fails the configured safety rules
- **THEN** the system refuses to render it as an active declaration and reports the validation failure

### Requirement: Export is review-only and non-mutating

The export workflow SHALL write only to stdout or an explicitly selected
operator-owned output path. It SHALL NOT modify Gitea, modify Nix source files,
activate configuration, create adoption markers, or commit to version control.

#### Scenario: Candidate is exported

- **WHEN** an operator runs the export workflow
- **THEN** Gitea records and the repository remain unchanged

#### Scenario: Export output is reviewed and edited

- **WHEN** an operator fills in secret paths or adjusts a candidate manually
- **THEN** no change is applied until the resulting Nix configuration is separately evaluated and activated

### Requirement: Adoption is distinct from export

The system SHALL treat adoption as a separate, explicitly requested operation.
Export alone SHALL NOT mark records as managed. If adoption is implemented, it
MUST require a selected record or allowlist and SHALL re-run all safety checks
before producing an adoptable result.

#### Scenario: Export is run without adoption

- **WHEN** an operator exports an unmanaged user
- **THEN** the user remains unmanaged in Gitea and no persistent adoption state is created

#### Scenario: Adoption is requested for an unsafe record

- **WHEN** an operator requests adoption of an administrator or conflicting record
- **THEN** adoption is refused and no configuration or Gitea mutation occurs

### Requirement: Reverse configuration is tested in a MicroVM

The Gitea MicroVM integration test SHALL export externally created users and
organizations from the running service and verify deterministic output, secret
omission, safety refusals, and non-mutating behavior.

#### Scenario: External user produces a candidate

- **WHEN** an unmanaged non-administrator user is exported
- **THEN** the candidate contains its supported identity fields, requires manual secret configuration, and contains no credential material

#### Scenario: Unsafe account is excluded

- **WHEN** an administrator or ownership-conflicted organization is selected
- **THEN** the output excludes it with a clear reason and does not change Gitea

#### Scenario: Export is repeated

- **WHEN** export is run twice against unchanged state
- **THEN** both outputs are identical and Gitea state is unchanged
