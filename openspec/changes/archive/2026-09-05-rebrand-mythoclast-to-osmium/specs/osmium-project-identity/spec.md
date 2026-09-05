## Purpose

Establishes Osmium as the canonical project and runtime identity while
preserving a safe, explicit migration path for existing Mythoclast deployments.

## ADDED Requirements

### Requirement: Osmium is the canonical public identity

The system SHALL use `osmium` as the canonical project, NixOS namespace,
service-unit prefix, executable prefix, schema namespace, generated-artifact
namespace, and documentation brand. New user-facing output, declarations,
runtime markers, and tests SHALL use Osmium names unless they are explicitly
documented compatibility or historical references.

#### Scenario: New configuration uses the canonical namespace

- **WHEN** an operator evaluates a new Osmium configuration
- **THEN** public options, units, commands, schemas, and generated artifacts use the `osmium` namespace

#### Scenario: New diagnostics are emitted

- **WHEN** an Osmium command or service reports status or failure
- **THEN** its user-facing identity uses `osmium` and does not introduce a new Mythoclast-prefixed identifier

#### Scenario: Historical material is inspected

- **WHEN** an operator reads archived changes or historical provenance
- **THEN** existing Mythoclast names remain intelligible and are not rewritten as if they were originally Osmium

### Requirement: Existing Mythoclast deployments have an explicit migration path

The system SHALL define how existing Mythoclast option declarations, service
units, commands, state directories, persistence markers, schema documents, and
runtime metadata are migrated to Osmium. Migration SHALL preserve valid service
state and SHALL be safe to repeat. The system MUST either provide a bounded
compatibility alias or fail with an actionable migration error for each
renamed public interface.

#### Scenario: Existing persisted state is upgraded

- **WHEN** an existing deployment contains Mythoclast state and the Osmium version is activated
- **THEN** the migration preserves usable state, records completion atomically, and makes the Osmium state available without silently deleting the old state first

#### Scenario: Migration runs twice

- **WHEN** the same migration is retried after completion
- **THEN** it does not duplicate state, rotate credentials, recreate records, or corrupt either namespace

#### Scenario: An old interface has no compatibility alias

- **WHEN** an operator uses a retired Mythoclast interface outside the supported migration window
- **THEN** the system fails clearly and identifies the Osmium replacement and required migration action

### Requirement: Namespace changes do not create duplicate services

The system SHALL prevent old and new names from causing two independent copies
of the same service, reconciliation workflow, timer, snapshot tracker, or
persistence record to operate concurrently. Compatibility aliases SHALL route
to the canonical Osmium implementation or be rejected; they SHALL NOT create a
second authoritative state path.

#### Scenario: Old and new options are both configured

- **WHEN** a configuration contains both Mythoclast and Osmium declarations for the same service
- **THEN** evaluation fails with an explicit conflict or deterministically merges them under documented rules without creating duplicate runtime units

#### Scenario: Old unit name is invoked during migration

- **WHEN** an operator starts a supported Mythoclast unit alias
- **THEN** it invokes the corresponding Osmium service or reports that migration is required, without operating a separate state directory

### Requirement: Rebranding preserves runtime behavior and secrets

The rebrand SHALL NOT change service behavior, ownership, persistence semantics,
credential bootstrap or rotation guarantees, drift safety, reverse-configuration
review boundaries, or secret-handling behavior except where a name migration is
required. Renaming SHALL NOT expose secret contents or copy credentials into
new artifacts or logs.

#### Scenario: Service state survives the rename

- **WHEN** an existing Gitea or filesystem-snapshot deployment is migrated to Osmium
- **THEN** its persisted records, repositories, snapshots, and completion state remain usable with the same behavior

#### Scenario: Credential state is migrated

- **WHEN** a service has bootstrap or rotation markers under the old namespace
- **THEN** migration preserves the non-secret state and does not repeat bootstrap or rotate credentials solely because of the rename

### Requirement: Repository naming is consistent and auditable

The implementation SHALL update active source, examples, tests, generated
documentation, flake outputs, and user-facing artifacts to the Osmium identity.
It SHALL provide an auditable allowlist of remaining `mythoclast` occurrences,
limited to historical records, migration aliases, compatibility diagnostics, or
external compatibility data. Validation SHALL fail for unexplained active
occurrences.

#### Scenario: Repository naming audit passes

- **WHEN** the rebrand verification is run
- **THEN** unexplained active Mythoclast occurrences are absent and every retained occurrence has a documented reason

#### Scenario: Generated output is inspected

- **WHEN** an operator generates a new configuration, report, or artifact
- **THEN** it uses Osmium identifiers except for explicitly required source-compatibility metadata

### Requirement: The rebrand is verified in MicroVMs

The integration tests SHALL boot the affected service MicroVMs and verify both
fresh Osmium deployment and migration from persisted Mythoclast-named state.
They SHALL exercise service behavior, persistence, lifecycle, command/unit
names, and compatibility or migration failure behavior rather than only
evaluating NixOS options or searching source text.

#### Scenario: Fresh Osmium deployment works

- **WHEN** a clean MicroVM is configured using only Osmium names
- **THEN** the service boots, its primary behavior works, and its canonical units, commands, state, and artifacts use Osmium names

#### Scenario: Existing deployment migrates

- **WHEN** a MicroVM is populated with valid Mythoclast-era persisted state and upgraded to the Osmium configuration
- **THEN** the state remains available, migration completes once, and service behavior remains correct after restart

#### Scenario: Namespace conflict is handled

- **WHEN** both old and new declarations attempt to configure the same service
- **THEN** the MicroVM test observes the documented conflict or merge behavior and no duplicate authoritative service is started
