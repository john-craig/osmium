## Purpose

Defines ownership-safe declarative local Paperless users, supported group permissions, and protected per-user API-token delivery.

## ADDED Requirements

### Requirement: Paperless users are declarative
The system SHALL accept stable local user declarations with username, email, display metadata, active state, staff state, superuser state, runtime password file, and supported group membership or permission settings. It SHALL reject duplicate identities, unsafe password paths, invalid permission references, bootstrap-administrator collisions, and unsupported privilege combinations before mutation. Reconciliation SHALL update only ownership-proven users and SHALL preserve unmanaged users.

#### Scenario: Declared user is created and authenticates
- **WHEN** a valid local user declaration is activated with a runtime password
- **THEN** Paperless creates or updates that user with the declared non-secret metadata and the user can authenticate through the web/API login flow

#### Scenario: Unmanaged user is preserved
- **WHEN** an operator creates a Paperless user outside the Osmium declaration
- **THEN** reconciliation does not adopt, modify, disable, or delete that user

### Requirement: User password changes reconcile at runtime
The system SHALL detect changes to each declared password file and update only the corresponding ownership-proven Paperless user without exposing either password value in evaluated configuration, persistent state, logs, observations, or diagnostics.

#### Scenario: Declared password rotates
- **WHEN** a managed user password file changes
- **THEN** reconciliation applies the replacement at runtime and the new password authenticates while unrelated users remain unchanged

### Requirement: One managed API token can be declared for each user
The system SHALL accept API-token declarations keyed by stable local names, each referencing exactly one declared Paperless user, protected output metadata, explicit persistence intent, and replacement/removal policy. Paperless API tokens SHALL be represented as user-owned tokens without a declarative scope field because Paperless does not provide independent token scopes; the token inherits the owning user’s Paperless permissions. Reconciliation SHALL create or retrieve only the ownership-proven token and SHALL atomically write its plaintext value only to the declared protected output path.

#### Scenario: User token is declared
- **WHEN** a valid API-token declaration references a declared Paperless user
- **THEN** exactly one managed token authenticates as that user, its value is written only to the protected output path, and its effective access matches the user’s Paperless permissions

#### Scenario: Unsupported token scopes are rejected
- **WHEN** a token declaration requests independent read/write scopes or other token capabilities not provided by Paperless
- **THEN** evaluation fails rather than pretending that the token has narrower permissions than its user

### Requirement: API-token replacement is explicit and safe
The system SHALL support an explicit token rotation trigger or recovery policy. When replacement is requested, reconciliation SHALL revoke or replace only the ownership-proven token, validate the new token against live Paperless API authentication, atomically replace its protected output, and retain the prior usable token/output if replacement fails. Unmanaged user tokens SHALL never be adopted, revoked, or modified.

#### Scenario: Managed token rotates
- **WHEN** the declared token rotation input changes
- **THEN** the managed user token is replaced, the replacement authenticates against the API, and the ledger contains no plaintext token or reversible token digest

### Requirement: Identity removal is ownership-safe
The system SHALL require explicit removal policy for managed users, groups, memberships, and tokens. Removal SHALL affect only resources proven by the ownership ledger, SHALL remove a managed token output only with its managed token, and SHALL preserve unmanaged users, groups, tokens, and documents.

#### Scenario: Managed user is removed
- **WHEN** a managed user is removed from the declaration with explicit deletion enabled
- **THEN** Paperless removes only the ownership-proven user and managed token, preserves documents according to the declared retention policy, and leaves unrelated identities intact

### Requirement: Identity reconciliation is exercised in a MicroVM
The system SHALL expose a `paperless-identities` flake check that boots Paperless, provisions local users, exercises group/permission behavior, uses each generated API token against live endpoints, rotates a token, proves unmanaged identity preservation, and verifies protected output and secret exclusion.

#### Scenario: Identity check executes live user and token behavior
- **WHEN** `nix build .#checks.x86_64-linux.paperless-identities --print-build-logs` runs
- **THEN** it boots a MicroVM and validates users, permissions, API-token authorization, token replacement, persistence, removal safety, and secret exclusion against the running service
