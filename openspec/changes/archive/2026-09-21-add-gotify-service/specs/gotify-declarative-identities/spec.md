## Purpose

Provides runtime-safe, declarative reconciliation of Gotify users and their
applications while delivering one-time application tokens through protected
operator-selected files.

## ADDED Requirements

### Requirement: Gotify users are declaratively configurable

The system SHALL accept Gotify user declarations keyed by stable local names.
Each declaration SHALL provide a unique username, a runtime password file, and
explicit non-administrator metadata. It MUST reject duplicate usernames,
administrator escalation, missing password files, and unsupported or ambiguous
fields before service mutation.

#### Scenario: User is declared

- **WHEN** an administrator is available and a valid user declaration is
  activated
- **THEN** reconciliation creates or updates exactly one corresponding
  non-administrator Gotify user using the runtime password input

#### Scenario: User password changes

- **WHEN** the content of a declared user's password file changes
- **THEN** reconciliation updates only that user's password at runtime without
  exposing either password value in evaluated configuration, state, logs, or
  diagnostics

### Requirement: Gotify applications and tokens are declaratively configurable

The system SHALL accept application declarations keyed by stable local names.
Each declaration SHALL identify exactly one declared user, application name,
description, and protected token output with path, owner, group, mode, and
persistence intent. Reconciliation SHALL create one application for each valid
declaration and atomically deliver its generated token only to the declared
output.

#### Scenario: Application token is declared

- **WHEN** a valid application declaration references an available declared user
- **THEN** reconciliation creates one application and writes its generated token
  to the declared protected output file

#### Scenario: Token output is unsafe

- **WHEN** an application output path is outside the approved area, aliases an
  unsafe existing file, or has invalid ownership or mode metadata
- **THEN** evaluation or reconciliation refuses the declaration before it
  generates or writes a token

### Requirement: Reconciliation is idempotent and preserves non-secret identity

The system SHALL persist a versioned, non-secret ledger containing declaration
keys, normalized user/application identities, Gotify identifiers, observable
metadata, output metadata, and completion status. It SHALL not retain token
values, password values, or reversible password/token digests. It MUST refuse
to duplicate or silently replace an application whose managed identity, remote
state, or output cannot be proven safe.

#### Scenario: Unchanged reconciliation repeats

- **WHEN** the service restarts with unchanged declarations, ledger, and token
  outputs
- **THEN** application identifiers and token files remain unchanged and no
  duplicate user or application is created

#### Scenario: Token output is lost

- **WHEN** a ledger entry identifies an existing application but its token output
  is missing or unreadable
- **THEN** reconciliation fails closed and requires explicit recovery rather
  than creating a replacement application or token

### Requirement: Removal affects only proven managed records

The system SHALL delete a user or application and remove its token output only
when a removed declaration matches a compatible managed-ledger identity. It
MUST preserve unrelated Gotify users, applications, and tokens, and SHALL
report failed cleanup without recording false success.

#### Scenario: Application declaration is removed

- **WHEN** a previously reconciled application declaration is absent from the
  next activation
- **THEN** its matching managed application is deleted and its managed token
  output is removed, while unrelated applications remain usable

#### Scenario: User removal is unsafe

- **WHEN** a removed user owns unmanaged applications or its remote identity
  conflicts with the managed ledger
- **THEN** reconciliation leaves the user and unrelated resources intact and
  reports the unresolved cleanup

### Requirement: Provisioning is tested in a MicroVM

The implementation SHALL provide `gotify-provisioning` as a flake check that
boots Gotify, bootstraps an administrator, provisions users and applications,
uses each generated application token to submit a notification, verifies output
protection and secret omission, restarts, tests password-file rotation, and
tests safe removal. The executable check command SHALL be `nix build
.#checks.x86_64-linux.gotify-provisioning --print-build-logs`.

#### Scenario: Provisioning integration check runs

- **WHEN** the Gotify provisioning flake check is executed
- **THEN** it proves application tokens work against the running server and
  proves restart reuse, changed-password reconciliation, removal behavior, and
  protected token delivery
