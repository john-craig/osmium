## Context

Homebox is a Go application with SQLite/PostgreSQL support, native OIDC, a REST API under `/api/v1`, and collection-scoped inventory. The API manages current-user credentials and some group operations, but does not provide complete administrator user or membership management. Homebox API keys are generated server-side, returned only once, and stored as hashes. See `proposal.md` and the capability specs for the required behavior.

## Goals / Non-Goals

**Goals:**

- Integrate Homebox with Osmium's native service and persistent MicroVM conventions.
- Use Homebox's native OIDC flow rather than a gateway because the browser protocol is supported directly.
- Reconcile owned users, groups, memberships, API keys, tags, entity types, templates, and template fields.
- Isolate direct database access to a version-gated runtime helper for operations unavailable through the supported API.
- Keep all credentials runtime-only and make reverse configuration reviewable and explicitly incomplete where needed.
- Verify API behavior and database-boundary behavior in booted MicroVMs.

**Non-Goals:**

- Declarative inventory entities, location/item records, attachments, maintenance history, imports/exports, notifiers, or bulk actions.
- A general Homebox fork or API extension.
- Automatic deletion of unmanaged users, groups, memberships, metadata, or API keys.

## Decisions

### Use the native package and OIDC flow

Use the nixpkgs Homebox package and the repository's native module/MicroVM patterns. Configure Homebox's own OIDC integration and preserve the reverse proxy's WebSocket behavior. A Keycloak gateway is unnecessary because Homebox implements an interactive OIDC browser flow.

Alternative considered: a gateway in front of Homebox. Rejected because it adds an identity boundary Homebox already supports and would complicate machine/API authentication.

### Separate supported API reconciliation from database bootstrap

Use the REST API for tags, entity types, templates, current-group operations, and observable API-key metadata. Use a small runtime helper against the configured database only for user creation/update, group creation where necessary, membership changes, and API-key state that the API cannot express. The helper must run against the application data directory or database connection with the Homebox service stopped or otherwise protected from concurrent writes.

Alternative considered: REST-only reconciliation. Rejected because the API has no general administrator user-management endpoint and membership addition is invitation-oriented rather than declarative.

### Gate direct database operations by version and migration state

The helper will identify the Homebox application version and database migration/schema state before reading or mutating rows. It will support only explicitly recognized versions, use parameterized queries or generated model-compatible operations, and fail closed when migrations are pending or the schema is unknown.

Alternative considered: query by table/column names without version checks. Rejected because internal schema changes could silently corrupt identities or ownership.

### Use UUID ownership mappings

Declarations retain Homebox UUIDs after creation, and the module maintains an ownership ledger mapping declaration identities to instance-local IDs. Names, email, paths, and asset IDs are discovery hints only; duplicate matches fail closed. Unmanaged records are preserved.

Alternative considered: name-only matching. Rejected because Homebox names are not universally unique and entity paths can change.

### Treat API keys as generated credentials

Homebox generates API-key values and returns the raw value once. The helper will store only non-secret ownership metadata, deliver the raw value to a protected runtime output, and reuse the ownership record on unchanged activations. A changed protected rotation-secret input triggers revocation of only the owned key and creation of a new generated key; the replacement raw key is delivered through the protected output path.

Alternative considered: declaring the desired raw API-key string. Rejected because Homebox does not accept caller-supplied key material and hashes the server-generated value.

### Exclude inventory and event-like state

Inventory entities, attachments, maintenance entries, imports/exports, duplicate operations, and bulk actions are excluded because POST operations create new records/jobs, attachments have independent storage semantics, and maintenance is history rather than desired configuration.

Alternative considered: manage all UUID-addressable records. Rejected because addressability does not provide idempotency or safe ownership semantics.

### Make reverse configuration runtime-derived and non-mutating

Drift conversion queries the service and compares owned state; live capture reads the running API and, only for supported identity fields, the compatible database helper. Output includes source provenance, ownership, omitted secrets, unsupported state, and completeness. It never adopts or mutates state automatically.

## Risks / Trade-offs

- **Homebox internal schema changes** -> Pin supported package versions, check migrations/schema state, maintain version-specific helper adapters, and fail closed for unknown versions.
- **Concurrent database writes** -> Coordinate helper execution with the Homebox service and refuse unsafe access rather than risking corruption.
- **API-key raw values are one-time outputs** -> Require protected output paths, never log values, persist ownership metadata separately, and report recovery as incomplete if the raw value is lost.
- **User and membership API boundaries differ from database state** -> Test both API-visible behavior and helper-created state in a booted MicroVM; preserve unmanaged identities.
- **OIDC and local accounts can coexist** -> Represent local-password and OIDC identities separately, never fabricate passwords for OIDC users, and require explicit identity-provider provenance.
- **Deletion cascades collection state** -> Disable deletion by default and require ownership plus dependency checks before any future delete policy.
- **Attachment/blob persistence can diverge from database state** -> Keep attachments out of the declarative scope and test only database/application persistence required by supported metadata.

## Migration Plan

1. Deploy Homebox with persistent database and storage paths, native OIDC configuration, and runtime secret inputs.
2. Start the service and verify the status endpoint, browser boundary, and OIDC redirect configuration.
3. Run the version-gated bootstrap helper for the declared initial user, group, memberships, and API-key outputs.
4. Reconcile supported collection metadata through the REST API and record UUID ownership.
5. Run service, identity, metadata, drift, and live-capture MicroVM checks.
6. Roll back by disabling the module or reverting the system generation while retaining persistent database/storage state.
