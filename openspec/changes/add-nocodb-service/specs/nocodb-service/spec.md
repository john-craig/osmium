## Purpose

Provides a persistent, secret-safe NocoDB Community Edition service that can run reliably inside an impermanent Osmium MicroVM.

## ADDED Requirements

### Requirement: NocoDB Community Edition is packaged and runs as an Osmium service
The system SHALL provide `services.osmium.nocodb` and a pinned, reproducible NocoDB package source because NocoDB is absent from nixpkgs. The service SHALL run under a dedicated unprivileged account, bind only its declared HTTP listener, expose an explicit MicroVM port forward, wait for an HTTP readiness endpoint before reconciliation, and persist all NocoDB-owned state outside the ephemeral guest root.

#### Scenario: Fresh MicroVM becomes ready
- **WHEN** a fresh MicroVM enables NocoDB with valid runtime inputs
- **THEN** NocoDB becomes reachable on its declared forwarded HTTP port and its reconciler runs only after live readiness succeeds

#### Scenario: Ephemeral guest root is recreated
- **WHEN** NocoDB state exists and the MicroVM guest root is recreated with the declared persistent volume retained
- **THEN** the service starts with its prior managed metadata, data, and ownership state intact

### Requirement: SQLite is the default backend and PostgreSQL is supported explicitly
The system SHALL use persistent SQLite for NocoDB metadata and managed data when no database backend is declared. It SHALL support a typed PostgreSQL connection configuration whose password is read only from a runtime secret file, validates endpoint and database identifiers, and never serializes the credential into the Nix store, process arguments, reports, candidates, or ownership ledger.

#### Scenario: Default SQLite deployment
- **WHEN** an operator enables NocoDB without a database declaration
- **THEN** NocoDB stores its metadata and managed data in the declared persistent SQLite location

#### Scenario: PostgreSQL credential is supplied at runtime
- **WHEN** an operator declares PostgreSQL and supplies its password file at runtime
- **THEN** NocoDB connects using the declared PostgreSQL endpoint without exposing the password in declarative outputs or service diagnostics

### Requirement: Administrator bootstrap and rotation are one-time and secret-safe
The system SHALL bootstrap the declared local administrator only once after NocoDB is ready, consume its initial credential exclusively from a runtime secret file, and persist a secret-free completion record. A changed replacement credential file SHALL trigger administrator credential rotation, verify authentication with the replacement, and retain the prior usable credential when a replacement cannot be applied or verified.

#### Scenario: Initial bootstrap is idempotent
- **WHEN** a new NocoDB service is started twice with the same valid bootstrap secret
- **THEN** exactly one local administrator exists and the second start does not recreate or rotate it

#### Scenario: Changed replacement secret rotates the administrator
- **WHEN** the declared administrator rotation secret changes after bootstrap
- **THEN** the service authenticates the administrator with the replacement credential and its persistent ledger contains no secret value

### Requirement: Lifecycle behavior is exercised in a MicroVM
The system SHALL expose a flake check named `nocodb` that boots a NocoDB MicroVM and verifies readiness, SQLite persistence, local-administrator bootstrap, changed-secret rotation, and secret exclusion with live HTTP behavior rather than evaluation-only assertions.

#### Scenario: NocoDB lifecycle check executes
- **WHEN** `nix build .#checks.x86_64-linux.nocodb --print-build-logs` runs
- **THEN** the check boots the MicroVM and verifies the required lifecycle behavior against the running service
