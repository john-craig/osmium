## Purpose

Defines ownership-safe declarative local users and Community Edition collaboration memberships for a NocoDB workspace and its bases.

## ADDED Requirements

### Requirement: Local users are declarative and reconciled safely
The system SHALL allow declarations for NocoDB-local users with stable email identity, display metadata, enabled state, and runtime-only password input. It SHALL reject duplicate identities, malformed email addresses, unsafe secret paths, and attempts to manage the bootstrap administrator as an ordinary user. Reconciliation SHALL create and selectively update only ownership-proven users and SHALL not adopt, delete, disable, or reset unmanaged users.

#### Scenario: Declared local user is created
- **WHEN** a valid managed local user is declared and NocoDB is ready
- **THEN** the user can authenticate with the declared runtime password and has the declared non-secret metadata

#### Scenario: Unmanaged user is preserved
- **WHEN** a user created outside the declaration has the same non-managed environment
- **THEN** reconciliation leaves that user unchanged and reports it as unmanaged where relevant

### Requirement: Workspace and base memberships are declarative
The system SHALL manage the Community Edition instance workspace, one owner, explicit local-user membership, and per-base local-user membership with supported workspace/base roles. It SHALL validate referenced users and bases, preserve each NocoDB singleton-owner constraint, make role precedence explicit, and apply only ownership-proven membership changes.

#### Scenario: Membership role is reconciled
- **WHEN** a declared local user has a supported base role and that role changes declaratively
- **THEN** the running base grants the updated role without changing unrelated members

#### Scenario: Invalid owner declaration is rejected
- **WHEN** a declaration assigns multiple workspace or base owners, or references a missing local user
- **THEN** evaluation fails before NocoDB state is mutated

### Requirement: Scoped per-user API tokens are declarative and secret-safe
The system SHALL allow an ownership-proven API-token declaration to reference a declared local user, a stable token name, a valid non-empty Community Edition scope set, optional supported base restrictions, a runtime-only output secret path, and explicit rotation/removal policy. It SHALL validate token scope identifiers against the pinned NocoDB version, reject duplicate user/name declarations and unsafe output paths, create or update only ownership-proven tokens, and write each minted plaintext token only to the declared root-readable runtime secret path. The ownership ledger SHALL retain only token identity, status, and salted fingerprints; it SHALL never retain the token value or scopes that reveal secrets. Unmanaged tokens SHALL not be adopted, modified, or removed.

#### Scenario: Scoped managed token authorizes its requested API behavior
- **WHEN** a declared user receives a managed API token with valid metadata and data scopes
- **THEN** the token is available only at its declared runtime secret path and authenticates the user for the allowed NocoDB API operations

#### Scenario: Invalid token scope is rejected before mutation
- **WHEN** a token declaration contains an unknown, empty, duplicated, or incompatible Community Edition scope
- **THEN** evaluation fails without creating a NocoDB token or output secret file

#### Scenario: Changed token secret input rotates only the managed token
- **WHEN** the token's declared rotation input changes after a token has been created
- **THEN** reconciliation replaces or revokes only the ownership-proven token, validates the replacement through a live API request, and records no plaintext token value

#### Scenario: Unmanaged token is preserved
- **WHEN** a user owns a token created outside the declaration
- **THEN** token reconciliation leaves that token unchanged

### Requirement: Removal behavior is explicit
The system SHALL require explicit removal policy for managed users, API tokens, and memberships. A policy that preserves resources SHALL remove no remote state; a policy that removes resources SHALL remove only ownership-proven resources after preventing orphaned workspace/base ownership and preserving base data unless separately removed through its base policy.

#### Scenario: Managed membership is removed safely
- **WHEN** an ownership-proven membership is removed from a declaration with explicit removal enabled
- **THEN** only that membership is removed and the user, unrelated memberships, and base records remain intact

### Requirement: Identity reconciliation is exercised in a MicroVM
The system SHALL expose a `nocodb-identities` flake check that boots NocoDB, provisions local users, scoped API tokens, and memberships, authenticates users and token API calls, verifies role and token rotation/removal behavior, proves unmanaged-user/token preservation, and excludes runtime secrets.

#### Scenario: Identity check executes live collaboration and token behavior
- **WHEN** `nix build .#checks.x86_64-linux.nocodb-identities --print-build-logs` runs
- **THEN** it boots a MicroVM and validates users, memberships, token scopes, token rotation, and secret exclusion through the running NocoDB APIs and authentication flow
