# lldap-declarative-identities Specification

## Purpose

Defines managed LLDAP users and groups with runtime-only credentials and safe,
reviewable lifecycle reconciliation through LLDAP's supported management API.

## Requirements

### Requirement: LLDAP identities are declaratively configurable

The system SHALL expose typed declarations for users, groups, enabled state,
identity metadata, memberships, runtime password files, and explicit removal
policy. Duplicate identities, malformed names, unsafe paths, dangling groups,
and unsupported attributes MUST fail before mutation.

#### Scenario: A declared identity is reconciled

- **WHEN** a valid user and group declaration is applied
- **THEN** the running LLDAP directory exposes the declared non-secret attributes and memberships exactly once

### Requirement: Credentials rotate through runtime files

Managed user passwords and dedicated consumer bind credentials SHALL be sourced
only from runtime files. A changed valid source SHALL replace the affected
credential and reject the prior value; an invalid replacement MUST preserve the
prior credential and secret-free completion state.

#### Scenario: Managed password changes

- **WHEN** a managed user's runtime password file changes to a valid value
- **THEN** live LDAP authentication rejects the old password and accepts the replacement

### Requirement: Managed lifecycle is safe and explicit

The system SHALL maintain a versioned secret-free ledger proving managed LLDAP
resources. Updates and removals SHALL affect only ownership-proven resources;
ambiguous or unmanaged records MUST remain unchanged. Reconciliation SHALL use
the supported GraphQL API and SHALL NOT modify the SQL database directly.

#### Scenario: Unmanaged identity collides with a declaration

- **WHEN** a declaration matches an existing identity without compatible ownership evidence
- **THEN** reconciliation reports the conflict without adopting, changing, or deleting the identity

### Requirement: Identity lifecycle is exercised in a MicroVM

The implementation SHALL provide a booting `lldap-identities` flake check. The
executable command SHALL be `nix build .#checks.x86_64-linux.lldap-identities
--print-build-logs`.

#### Scenario: Identity integration check runs

- **WHEN** the LLDAP identities check is executed
- **THEN** it boots a MicroVM and verifies provisioning, LDAP authentication, password rotation, safe removal, persistence, and secret exclusion
