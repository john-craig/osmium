## Purpose

Provides Paperless-ngx as a persistent, secret-safe Osmium MicroVM service using the existing nixpkgs package and NixOS service configuration.

## ADDED Requirements

### Requirement: Paperless uses the native NixOS service and package
The system SHALL provide `services.osmium.paperless` backed by the pinned nixpkgs `paperless-ngx` package and upstream `services.paperless` configuration. It SHALL preserve supported Paperless settings, including the web port/address, data/media/consume/export directories, environment file, OCR settings, database/broker settings, Tika/Gotenberg settings, and exporter settings, without silently discarding valid upstream configuration.

#### Scenario: Native Paperless configuration is preserved
- **WHEN** an operator supplies valid upstream Paperless settings through the Osmium service
- **THEN** the running Paperless process receives the equivalent configuration and reaches its health endpoint

#### Scenario: Invalid upstream configuration fails safely
- **WHEN** a setting is invalid for the pinned Paperless package or conflicts with the Osmium persistence/network boundary
- **THEN** evaluation or startup fails with a diagnostic before document data is mutated

### Requirement: Paperless state and documents persist
The system SHALL persist Paperless data, media, consumption, export, static/index, and local SQLite state under the Osmium persistence boundary with correct service ownership. It SHALL support the native PostgreSQL backend and broker configuration through runtime-only credentials and explicit dependency ordering. Guest-root recreation SHALL preserve documents, search metadata, and user state.

#### Scenario: Documents survive guest recreation
- **WHEN** a document is consumed and the impermanent MicroVM root is recreated with the declared persistent volume retained
- **THEN** the document, extracted metadata, searchable index, and Paperless user state remain available

#### Scenario: PostgreSQL credentials remain runtime-only
- **WHEN** Paperless is configured to use PostgreSQL with a password in a runtime environment file
- **THEN** Paperless connects after the database is ready and the password is absent from Nix store paths, generated declarations, logs, and process arguments

### Requirement: Paperless secrets are runtime-only
The system SHALL require a stable runtime Paperless secret key and SHALL consume administrator, user, database, broker, mail, OCR-provider, and other sensitive settings from protected runtime files or environment files. Secret values SHALL not be embedded in evaluated options, Nix store paths, ownership ledgers, observations, candidates, or diagnostics.

#### Scenario: Secret key remains stable
- **WHEN** Paperless restarts with the same declared runtime secret-key file
- **THEN** existing sessions and API tokens remain cryptographically valid and the service does not generate a replacement key

### Requirement: Paperless lifecycle is exercised in a MicroVM
The system SHALL expose a `paperless` flake check that boots Paperless, verifies readiness, consumes a representative document through the consumption directory, searches for it through the live API, verifies persistence after restart/recreation, and proves runtime-secret exclusion.

#### Scenario: Paperless lifecycle check executes
- **WHEN** `nix build .#checks.x86_64-linux.paperless --print-build-logs` runs
- **THEN** it boots a MicroVM and exercises live Paperless document ingestion, search, persistence, and secret-safe operation
