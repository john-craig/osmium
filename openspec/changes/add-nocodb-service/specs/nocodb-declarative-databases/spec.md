## Purpose

Defines complete Community Edition declarative control of the NocoDB workspace hierarchy, schema, views, collaboration, and initial data.

## ADDED Requirements

### Requirement: Community workspace and bases are declarative
The system SHALL declare the single Community Edition workspace and managed bases, treating NocoDB's legacy project terminology as a base rather than exposing duplicate project and base resources. A base declaration SHALL support all Community Edition API-representable base metadata, privacy/access settings, explicit ownership, memberships, and a removal policy. The system SHALL reject organization resources, duplicate names within their NocoDB scope, unsafe identifiers, dangling owner references, and licensed-only attributes before mutation.

#### Scenario: Managed base is reconciled
- **WHEN** a valid base declaration is applied
- **THEN** the running workspace contains a base with the declared Community Edition metadata, owner, access configuration, and membership behavior

#### Scenario: Project alias is not a second resource kind
- **WHEN** an operator describes a NocoDB project in a declaration or capture
- **THEN** it is represented as a base and cannot result in two independently managed resources for the same NocoDB base

### Requirement: Tables and complete Community schema are declarative
The system SHALL support all NocoDB Community Edition metadata API-representable table, field, index/constraint, relation, formula, lookup, rollup, select-option, validation/default, display-value, and table-configuration attributes that NocoDB exposes for the pinned version. Declarations SHALL use stable logical references rather than generated NocoDB IDs, validate cross-table references and type-specific settings before mutation, reconcile only ownership-proven schema resources, and refuse destructive type or relation changes unless the declaration explicitly permits them.

#### Scenario: Relational schema is created
- **WHEN** a base declares two tables with typed fields and a declared relation
- **THEN** the running base exposes the requested tables, fields, and relation through its metadata API

#### Scenario: Destructive schema change needs opt-in
- **WHEN** a declaration changes a managed field or relation in a way that NocoDB classifies as destructive
- **THEN** reconciliation fails without changing the live schema unless its explicit destructive-change policy permits that change

### Requirement: Views and their complete supported configuration are declarative
The system SHALL support all Community Edition API-representable collaborative view types and their supported view metadata, field visibility/order, filters, sorting, grouping, coloring, row height, locking, and sharing configuration. It SHALL not adopt personal or unmanaged views and SHALL reject licensed-only, unsupported, or ambiguous view state.

#### Scenario: Managed view is reconciled
- **WHEN** a table declares a supported collaborative view with filters, ordering, and visible fields
- **THEN** the running table returns the corresponding managed view configuration

### Requirement: Initial records and links are declarative without taking over runtime data
The system SHALL support idempotent initial record declarations for managed tables, including values, attachments represented by declared sources, and links resolved through declared stable keys. It SHALL require a declared unique match key per managed record, preserve unmanaged records, and permit updates or deletion of managed records only under explicit content and removal policies.

#### Scenario: Stable-key records are reconciled
- **WHEN** a table declares initial records with unique keys and a relation to another declared table
- **THEN** the running base contains the keyed records with the declared values and links after repeated reconciliation

#### Scenario: Unmanaged records are preserved
- **WHEN** an operator creates an additional record in a managed table outside Osmium
- **THEN** record reconciliation leaves the additional record unchanged

### Requirement: Database reconciliation is exercised in a MicroVM
The system SHALL expose a `nocodb-databases` flake check that boots NocoDB and verifies live reconciliation of workspace, bases, tables, typed fields, relations, views, roles, initial records, link resolution, destructive-change denial, explicit managed removal, and unmanaged-data preservation.

#### Scenario: Database check validates live state
- **WHEN** `nix build .#checks.x86_64-linux.nocodb-databases --print-build-logs` runs
- **THEN** it boots a MicroVM and queries the running metadata and data APIs to validate the represented hierarchy and data behavior
