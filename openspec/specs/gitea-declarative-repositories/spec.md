# gitea-declarative-repositories Specification

## Purpose

Provides reproducible, non-destructive provisioning and reverse configuration
for repositories owned by Mythoclast-managed Gitea users and organizations.

## Requirements

### Requirement: Repositories are declaratively configurable by owner

The system SHALL accept a declarative collection of repositories identified by
an owner and repository name. The owner SHALL be either a declared or existing
Gitea user or organization. Repository declarations SHALL support the metadata
implemented by the module, including description, private visibility, default
branch, website, and issue/wiki/pull-request feature settings where supported.
Repository content and history SHALL NOT be implied by metadata declarations.

#### Scenario: User-owned repository is declared

- **WHEN** a valid repository declaration references an available non-admin user
- **THEN** the repository exists under that user with the declared supported metadata

#### Scenario: Organization-owned repository is declared

- **WHEN** a valid repository declaration references an available organization
- **THEN** the repository exists under that organization with the declared supported metadata

#### Scenario: Owner is not available

- **WHEN** a repository references an undeclared and unavailable owner
- **THEN** evaluation or reconciliation fails clearly and does not create the repository under another owner

### Requirement: Repository reconciliation is idempotent and non-destructive

The system SHALL reconcile repository declarations after Gitea is available and
on configuration activation. Reconciliation SHALL find existing repositories by
stable owner and name, SHALL update only supported declarative metadata, and
SHALL NOT duplicate, transfer, fork, or overwrite repository content. Removing
a declaration SHALL NOT delete the existing repository by default.

#### Scenario: Existing repository matches declaration

- **WHEN** reconciliation finds a repository with the declared owner and name
- **THEN** it leaves content intact and applies no unnecessary duplicate creation

#### Scenario: Repository metadata changes

- **WHEN** a declared description, visibility, default branch, or supported feature setting changes
- **THEN** a later reconciliation updates that metadata without changing repository identity or content

#### Scenario: Declaration is removed

- **WHEN** a repository is removed from the declarative configuration
- **THEN** the existing repository and its content remain intact and no destructive cleanup is attempted

### Requirement: Invalid or conflicting repository declarations fail safely

The system SHALL reject empty or unsafe owner/name values, duplicate declaration
identities, unsupported metadata values, ambiguous owner types, and declarations
that would conflict with administrator or external-identity constraints.
Validation SHALL occur before repository mutation and SHALL report which
declaration is invalid.

#### Scenario: Duplicate repository identity is declared

- **WHEN** two declarations resolve to the same owner and repository name
- **THEN** configuration evaluation fails before reconciliation begins

#### Scenario: Repository name is unsafe

- **WHEN** a repository name cannot be represented safely by the Gitea API or declaration key rules
- **THEN** evaluation fails with an actionable validation error

#### Scenario: Existing repository has an incompatible owner

- **WHEN** a declaration cannot resolve its owner to exactly one supported Gitea identity
- **THEN** reconciliation reports the conflict and does not create or transfer a repository

### Requirement: Repository drift can be converted into a declaration

The system SHALL compare observed repository ownership and supported metadata
with declared repository attributes and SHALL provide a deterministic,
reviewable conversion of observed drift into Mythoclast repository declarations.
The conversion SHALL preserve the stable owner and repository name, identify
changed fields, and SHALL not mutate Gitea, Nix source, or adoption state.

#### Scenario: Unmanaged user repository is observed

- **WHEN** drift detection observes a safe repository owned by a supported user
- **THEN** the reverse-configuration output contains a repository declaration candidate with its supported metadata

#### Scenario: Unmanaged organization repository is observed

- **WHEN** drift detection observes a safe repository owned by a supported organization
- **THEN** the output contains a candidate referencing that organization without inventing a different owner

#### Scenario: Repository metadata drifts

- **WHEN** an observed repository differs from its declaration in supported metadata
- **THEN** drift identifies each changed attribute and provides a reviewable conversion containing the observed values

#### Scenario: Drift conversion is repeated

- **WHEN** the same normalized repository observation is converted more than once
- **THEN** the generated declarations and machine-readable report are byte-for-byte identical

### Requirement: Repository state can be captured live and converted into a declaration

The system SHALL capture repository ownership and supported metadata from a
running Gitea service through its approved runtime interface and SHALL convert
the live observation into a deterministic Mythoclast declaration candidate.
Capture and conversion SHALL record provenance and completeness and SHALL
distinguish observed values from operator-supplied values.

#### Scenario: Live capture includes repositories for multiple owners

- **WHEN** a running Gitea service contains repositories owned by users and organizations
- **THEN** the capture and conversion output includes each supported repository with the correct owner reference

#### Scenario: Live capture is partially unavailable

- **WHEN** pagination, ownership, or a required repository field cannot be captured
- **THEN** the output records the failed or missing observation and does not claim to represent the full repository configuration

#### Scenario: Live capture is repeated

- **WHEN** unchanged repository state is captured twice
- **THEN** normalized capture and converted declaration output are deterministic regardless of API response order

### Requirement: Reverse configuration is secret-safe and explicit about unsupported state

Drift and live-capture conversion SHALL never emit passwords, password hashes,
access tokens, deploy keys, webhook secrets, private keys, repository contents,
or other secret material. They SHALL report repositories with unsupported
features, ambiguous ownership, external identity records, administrator-only
state, content/history requirements, or missing metadata as machine-readable
incomplete findings. An incomplete result SHALL NOT pass the default readiness
or activation validation.

#### Scenario: Repository contains sensitive integration data

- **WHEN** observed repository state includes webhook secrets, deploy keys, or tokens
- **THEN** conversion omits the values and reports only a redacted finding or unresolved requirement

#### Scenario: Repository content is not represented

- **WHEN** a repository requires Git content or history to reproduce its intended state
- **THEN** metadata conversion marks that requirement outside scope and does not claim full repository reconstruction

#### Scenario: Ambiguous owner is observed

- **WHEN** a repository cannot be mapped to exactly one supported user or organization declaration
- **THEN** conversion excludes it from an activation-ready candidate and reports the ownership ambiguity

### Requirement: Repository reverse configuration is verified in MicroVMs

The implementation SHALL include separate MicroVM integration tests for
repository drift conversion and live-system capture conversion. Each test SHALL
boot and exercise the running Gitea service, create or mutate repository state
through the runtime path, generate its reverse-configuration input from that
runtime observation, and verify the resulting declaration behavior. Tests MUST
NOT use an independently authored equivalent repository fixture as the
conversion input.

#### Scenario: Drift conversion is exercised end to end

- **WHEN** a MicroVM mutates repository ownership-safe metadata after a declared baseline
- **THEN** the drift-based conversion produces a candidate from the observed runtime drift and a separate evaluation or reconciliation applies the expected metadata

#### Scenario: Live capture conversion is exercised end to end

- **WHEN** a MicroVM contains externally created user-owned and organization-owned repositories
- **THEN** live capture produces the candidate from the running service and a separate Mythoclast test consumes it to provision equivalent repository metadata

#### Scenario: Reverse conversion does not mutate source state

- **WHEN** either MicroVM reverse-configuration test completes capture and conversion
- **THEN** the source repositories, contents, owners, and service state remain unchanged until the separately selected declaration is applied
