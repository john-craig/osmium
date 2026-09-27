## Purpose

Provides secret-safe, idempotent declarations for Vaultwarden users and
organization vaults while preserving client-side encryption boundaries.

## ADDED Requirements

### Requirement: Users are declaratively configurable

The system SHALL accept stable declarations for Vaultwarden users including
email, display metadata, enabled state, and supported account policy. A user MAY
reference a protected runtime master-password file. Master-password declaration
MUST be optional; when absent, provisioning SHALL create or reconcile the
account without inventing a password and SHALL report that user activation
requires native user setup.

#### Scenario: User is provisioned without a master password

- **WHEN** a valid user declaration omits a master-password file
- **THEN** the user account and non-secret attributes are provisioned, no
  password is generated or stored, and the result identifies the unresolved
  native credential requirement

#### Scenario: User master password is provisioned and rotated

- **WHEN** a valid user declaration references a protected password file and its
  content later changes
- **THEN** reconciliation applies the password replacement through supported
  Vaultwarden behavior, rejects the previous password, accepts the replacement,
  and persists only non-reversible rotation metadata

#### Scenario: User master password replacement is invalid

- **WHEN** a referenced password file is empty, unreadable, malformed, or
  rejected by Vaultwarden
- **THEN** the prior usable credential and secret-free completion state remain
  intact and the replacement is not recorded as applied

### Requirement: Personal-vault item provisioning is out of scope

The service MUST NOT provision, rewrite, or delete ciphers in an individual
user's personal vault. User declarations MAY establish account identity and
credentials, but any personal-vault item state SHALL be reported as unsupported
or unmanaged rather than inferred from the declarative configuration.

#### Scenario: Personal-vault cipher is encountered

- **WHEN** reconciliation or observation finds a cipher owned by a user's
  personal vault
- **THEN** it leaves the cipher unchanged and does not claim declarative
  ownership or completeness for that item

### Requirement: Organizations and collections are declaratively configurable

The system SHALL accept stable declarations for organizations, organization
metadata, collections, and organization membership. Each organization SHALL
reference provisioned users by stable declaration identity, define explicit
membership role and collection access, and reconcile in dependency order.
Unsupported invitations, external users, policies, or ownership states MUST fail
closed rather than being silently adopted.

#### Scenario: Organization and members are provisioned

- **WHEN** an organization references declared users with valid roles and
  collection access
- **THEN** the organization, collections, and memberships exist with the
  declared relationships and no unintended administrator privilege

#### Scenario: Organization references an unknown user

- **WHEN** an organization membership references a user that is not declared or
  cannot be matched to a managed Vaultwarden account
- **THEN** evaluation or reconciliation fails before creating an unintended
  membership

#### Scenario: Membership access changes

- **WHEN** a managed member's role or collection access changes
- **THEN** reconciliation updates only that managed membership and preserves
  unrelated members and collections

### Requirement: Organization-vault ciphers use pre-encrypted payloads

The system SHALL support declarative organization-vault secrets only as
pre-encrypted Bitwarden-compatible cipher payloads with the required
organization encryption metadata and stable cipher identity. The reconciler
MUST NOT receive, generate, log, or persist plaintext organization-vault secret
values or user master-password-derived keys. Cipher payload files MUST be
runtime-only or otherwise protected inputs and MUST be excluded from generated
desired-state and ownership ledgers.

#### Scenario: Pre-encrypted organization cipher is provisioned

- **WHEN** a valid organization cipher declaration references a compatible
  encrypted payload and an existing collection
- **THEN** the cipher is created or updated in the organization vault with the
  declared stable identity and no plaintext secret enters the service

#### Scenario: Cipher payload is invalid or incompatible

- **WHEN** an encrypted payload lacks required fields, targets an unknown
  organization or collection, or cannot be accepted by the supported API
- **THEN** reconciliation fails closed, leaves the prior cipher unchanged, and
  does not mark the replacement complete

### Requirement: Provisioning is idempotent, owned, and secret-safe

The system SHALL maintain a protected versioned ledger containing only stable
resource identities, non-secret metadata, ownership proofs, and non-reversible
change metadata. Reconciliation SHALL be ordered, retryable, and idempotent.
Removal SHALL affect only ledger-owned users, organizations, collections,
memberships, and organization ciphers under an explicit removal policy;
unmanaged or ambiguous resources MUST remain unchanged.

#### Scenario: Reconciliation repeats

- **WHEN** the same user, organization, membership, collection, and cipher
  declarations are reconciled twice
- **THEN** each resource remains singular with the same supported attributes and
  no duplicate invitation, membership, or cipher is created

#### Scenario: Ownership is ambiguous

- **WHEN** live state cannot be matched to a stable declaration and ledger
  identity
- **THEN** reconciliation reports the ambiguity and performs no destructive or
  credential-changing mutation

### Requirement: Provisioning is verified in a MicroVM

The implementation SHALL provide a booting MicroVM check that provisions users,
optional master-password rotation, organizations, collections, memberships, and
pre-encrypted organization ciphers, then verifies native client behavior,
persistence, idempotence, failure preservation, and the absence of personal-vault
item provisioning. The executable command SHALL be `nix build
.#checks.x86_64-linux.vaultwarden-provisioning --print-build-logs`.

#### Scenario: End-to-end organization vault provisioning runs

- **WHEN** the provisioning check executes against the running Vaultwarden API
- **THEN** declared organization state and encrypted ciphers are usable by the
  declared members after reconciliation and lifecycle restart
