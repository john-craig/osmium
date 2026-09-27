# keycloak-declarative-configuration Specification

## Purpose

Defines reproducible Keycloak realms, cryptographic keys, clients, authorization
metadata, users, and credentials while keeping all secret values runtime-only.

## Requirements

### Requirement: Realm resources are declaratively configurable

The system SHALL expose typed declarations for realms, enabled state, display
metadata, login policy, client scopes, realm roles, client roles, groups,
group-role mappings, users, user-group mappings, and user-role mappings. Stable
declaration keys and remote identifiers SHALL make reconciliation deterministic
and idempotent. Invalid references, duplicate identities, unsupported settings,
and ambiguous ownership MUST fail before mutation.

#### Scenario: A complete realm is reconciled

- **WHEN** a valid realm declaration references roles, groups, users, and
  mappings in dependency order
- **THEN** the running realm exposes each resource exactly once with the
  declared non-secret attributes and relationships

#### Scenario: A declaration has an invalid reference

- **WHEN** a mapping references an undeclared realm, client, role, group, or user
- **THEN** evaluation fails with the offending declaration path before Keycloak
  is mutated

### Requirement: OIDC clients are declaratively configurable

The system SHALL expose typed public and confidential OpenID Connect client
declarations including client ID, enabled state, redirect URIs, web origins,
protocol, supported authorization flows, consent behavior, scopes, and role
mappings. Unsafe wildcard redirects, unsupported flows, and browser clients
without an allowed redirect MUST be rejected.

#### Scenario: Confidential client is provisioned

- **WHEN** a valid confidential client and its runtime secret file are declared
- **THEN** Keycloak exposes the declared client metadata and accepts the
  declared secret without storing that secret in evaluated configuration

#### Scenario: Unsafe redirect is declared

- **WHEN** a client declaration contains a wildcard or non-HTTPS redirect that
  is not explicitly permitted for the isolated test environment
- **THEN** evaluation rejects the client rather than broadening its redirect
  policy

### Requirement: User account credentials are declarative and rotatable

Each managed local user SHALL support declared username, enabled state, email,
name, email-verification state, required actions, groups, roles, and a runtime
password file. Reconciliation SHALL set the desired non-temporary password and
SHALL change it when the file content changes. It SHALL retain only protected,
salted change-detection state and MUST NOT expose password bytes or reversible
digests. Federated and externally managed credentials SHALL be reported as
unsupported rather than overwritten.

#### Scenario: User signs in with a declared password

- **WHEN** a managed user is created from a valid password file
- **THEN** the user can complete an OpenID Connect authorization flow with that
  password and receives the declared groups and roles in supported claims

#### Scenario: User password file changes

- **WHEN** a managed user's password file receives a different valid value
- **THEN** reconciliation invalidates the old password, accepts the replacement,
  and leaves unrelated users unchanged

#### Scenario: Existing user has unsupported credentials

- **WHEN** a declaration collides with a federated or otherwise unmanaged user
  whose ownership cannot be proven
- **THEN** reconciliation fails without adopting or changing that account

### Requirement: Client credentials are runtime-only and rotatable

Each managed confidential client SHALL consume its desired client secret from a
runtime file. A changed file value SHALL rotate the Keycloak client credential,
invalidate the old value, and preserve the prior usable value if replacement
fails. Completion records, logs, diagnostics, and observations MUST omit client
secret values and reversible digests.

#### Scenario: Client secret file changes

- **WHEN** a confidential client's secret file receives a different valid value
- **THEN** the old client secret fails, the replacement succeeds, and only that
  managed client is changed

#### Scenario: Client secret replacement fails

- **WHEN** Keycloak rejects or cannot consume the replacement client secret
- **THEN** the prior credential remains usable and reconciliation does not mark
  the replacement complete

### Requirement: Realm signing keys are declarative and rotatable

The system SHALL support declared realm signing key providers with stable names,
algorithm, priority, enabled state, active-signing state, runtime private-key
file, and matching certificate or public-key file. It SHALL verify key pairing
before mutation. Changed key-file content SHALL install the replacement as the
declared active key while retaining the previous public verification key for a
declared overlap interval; expired retained keys SHALL be removable only after
the overlap. Private key bytes MUST remain runtime-only and MUST NOT appear in
Keycloak exports, local ledgers, logs, diagnostics, or reverse configuration.

#### Scenario: Declared signing key issues tokens

- **WHEN** a realm has a valid active signing-key declaration
- **THEN** newly issued tokens use that key identifier and verify against the
  realm's published JSON Web Key Set

#### Scenario: Signing key file changes

- **WHEN** the active signing key and matching certificate files change
- **THEN** newly issued tokens use the replacement key while tokens issued with
  the previous key remain verifiable for the declared overlap interval

#### Scenario: Signing key pair is invalid

- **WHEN** a private key and certificate do not match or use an unsupported
  algorithm
- **THEN** reconciliation fails before changing the active signing key and the
  prior key remains operational

### Requirement: Managed lifecycle is safe and explicit

The system SHALL maintain a versioned, protected, non-secret ledger that proves
which Keycloak resources it manages. Removal SHALL affect only resources whose
stable identity and ownership match that ledger. Destructive realm removal
SHALL require an explicit deletion policy; retained resources SHALL be reported
as retained rather than silently treated as reconciled. Interrupted operations
MUST be retryable without duplicate resources.

#### Scenario: Managed child resource is removed

- **WHEN** a managed user, group, role, mapping, client, scope, or inactive key
  is removed from the declaration and safe ownership is proven
- **THEN** reconciliation applies its declared removal policy without changing
  unmanaged resources

#### Scenario: Resource ownership is ambiguous

- **WHEN** a removal or update cannot be matched to compatible ledger identity
  and live metadata
- **THEN** reconciliation fails closed and reports the ambiguity without mutation

### Requirement: Declarative configuration is exercised in a MicroVM

The implementation SHALL provide a flake check that boots Keycloak, reconciles a
representative realm with all supported resource kinds, authenticates a user,
validates claims and signatures, changes administrator, user, client, and
signing-key files, and proves rotation and persistence. The executable command
SHALL be `nix build .#checks.x86_64-linux.keycloak-provisioning
--print-build-logs`.

#### Scenario: Provisioning integration check runs

- **WHEN** the provisioning check is executed
- **THEN** it exercises the running Keycloak APIs and OIDC protocol rather than
  only evaluating options or building a closure
