## Context

Grocy is a PHP application with a REST API, generic CRUD endpoints for reference entities, user-management endpoints, and API-key authentication. Its stock, shopping-list, completion, consumption, and execution endpoints are transactional and are not safe to replay during declarative activation. See `proposal.md` and the capability specs for the required behavior.

## Goals / Non-Goals

**Goals:**

- Fit Grocy into Osmium's existing NixOS module and MicroVM service conventions.
- Keep application data persistent while keeping passwords and API-token material runtime-only.
- Reconcile only explicitly owned users and stable reference data.
- Make ambiguity, ownership gaps, unsupported fields, and incomplete reverse configuration fail closed and reviewable.
- Verify service behavior, persistence, token lifecycle, reconciliation, drift conversion, and live capture in booted MicroVMs.

**Non-Goals:**

- Declarative management of products, barcodes, recipes, recipe positions, chores, tasks, stock, shopping-list contents, or event/history records.
- Replacing Grocy's interactive UI or adding a second authorization system.
- Automatic deletion of unmanaged Grocy records.

## Decisions

### Use the native Grocy package and service boundary

Build the module around nixpkgs' `grocy` package and the repository's existing service/MicroVM conventions rather than introducing a container deployment. This keeps package updates and PHP runtime dependencies in the system closure. The service should expose only the configured listener and use the existing reverse-proxy boundary where applicable.

Alternative considered: a containerized Grocy deployment. Rejected because it duplicates lifecycle and persistence integration already provided by the native module model.

### Use a persistent application data directory

Keep Grocy's database and application state under the service's persistent data path. Runtime-generated ledgers and completion markers belong alongside service state but must not contain plaintext credentials unless the existing secret-storage convention explicitly permits it.

Alternative considered: storing state in `/run`. Rejected because MicroVM replacement would lose Grocy data and ownership identity.

### Reconcile through the Grocy API with an ownership ledger

The activation path will query the running instance, match declarations using stable natural identities, and retain Grocy's instance-local integer IDs in an ownership ledger. It will create missing records, update only proven owned records, preserve unmanaged records, and stop on ambiguity. Generic POST/PUT/DELETE calls must never be replayed blindly.

Alternative considered: matching by integer IDs only. Rejected because IDs are instance-local and can change across imports or restores.

### Treat API tokens as owned credentials with explicit rotation

A declared user may have one owned token. Bootstrap and rotation consume protected runtime secret inputs, persist completion/ownership state, and avoid repeated creation. A changed secret-file value is the explicit rotation trigger. Token values are never included in Nix evaluation, logs, drift output, or live-capture output.

Alternative considered: derive tokens deterministically from Nix configuration. Rejected because this would place credential material in evaluation artifacts and make rotation unsafe.

### Separate reference reconciliation from operational state

Locations, quantity units, conversions, product groups, and shopping locations are treated as bounded reference data. Products, recipes, chores, tasks, stock, shopping-list entries, and history remain user-managed through Grocy because their APIs can create irreversible or duplicate events.

Alternative considered: support all Grocy entities through generic CRUD. Rejected because API shape alone does not make transactional state idempotent or safe to delete.

### Make reverse configuration review-only and runtime-derived

Implement drift conversion and live capture as non-mutating commands or checks. Drift conversion compares declared state with observed state; live capture queries the running Grocy API. Both emit provenance, ownership status, unsupported-state notices, and completeness metadata. Secret values and excluded operational state are omitted rather than guessed.

Alternative considered: generate declarations from static fixtures or configuration evaluation. Rejected because it would not prove runtime capture and could silently claim unsupported state is complete.

## Risks / Trade-offs

- **Grocy API schema varies by package version** -> Discover supported entity fields and endpoints from the installed OpenAPI specification at implementation/test time; reject unsupported attributes explicitly.
- **Natural keys can be duplicated or renamed** -> Require unique matches or an ownership-ledger match; fail closed on ambiguity and report the candidate records.
- **Permission and administrator changes are security-sensitive** -> Validate privileged declarations explicitly, avoid adopting unmanaged administrators, and test bootstrap and denial behavior in the MicroVM.
- **Token replacement semantics may differ across Grocy versions** -> Exercise create, reuse, and changed-secret rotation against the packaged version before exposing the option as complete.
- **Reverse capture cannot reproduce secrets or transactions** -> Mark results incomplete, provide runtime secret-input references, and report excluded operational state instead of generating replayable actions.
- **Deletion can invalidate dependent reference data** -> Preserve records by default and require explicit future policy before implementing deletion.

## Migration Plan

1. Deploy Grocy with a persistent data path and runtime secret files.
2. Run the service's one-time bootstrap and verify the health/API boundary.
3. Reconcile declared users and reference records, recording ownership only after successful API responses.
4. Run the service, identity, reference-data, drift, and live-capture MicroVM checks.
5. Roll back by disabling the module or reverting the system generation; retain the persistent Grocy data path so rollback does not destroy application state.
