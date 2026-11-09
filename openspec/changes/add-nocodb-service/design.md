## Context

See `proposal.md` for motivation. Osmium services are NixOS modules running in impermanent MicroVMs, with persistent state mounted at `/persistent`, runtime-only input secrets, idempotent systemd reconciliation, and flake checks that boot the actual service. Gitea and Keycloak provide the closest patterns: they use a dedicated account, readiness ordering, a secret-free ownership ledger, one-time bootstrap, changed-secret rotation, and review-only reverse configuration.

NocoDB is not in nixpkgs. Its current Community Edition exposes local authentication and metadata/data APIs, but native OIDC/SAML/SCIM, organizations, organization roles, and several collaboration features are licensed. Its legacy “project” identifier represents the resource now called a base. API tokens are minted values rather than user-supplied secrets, so their lifecycle differs from password rotation.

## Goals / Non-Goals

**Goals:**

- Run pinned NocoDB Community Edition without containers, with a local SQLite default and explicit PostgreSQL metadata backend support.
- Reconcile every Community Edition API-representable declared resource: local users, managed API tokens, workspace/base memberships, bases, schema, relations, views, and stable-key initial records.
- Make all mutation ownership-scoped, idempotent, and explicit about destructive removal.
- Keep every credential source and generated API token outside the Nix store and exclude secret values from logs, observations, candidates, and ledgers.
- Verify lifecycle, reconciliation, authorization, persistence, rotation, and reverse conversion in booting MicroVMs.

**Non-Goals:**

- Implement NocoDB Enterprise/Cloud capabilities, including organizations, teams, native SSO, SCIM, or record-level security.
- Treat an upstream Keycloak gateway as a NocoDB login integration; Community Edition cannot consume it as a mapped NocoDB session.
- Reconcile arbitrary external data sources, automations, interfaces, scripts, dashboards, documents, extensions, attachments uploaded manually, public links, or unmanaged records/views/tables.
- Import or migrate an existing NocoDB deployment automatically.

## Decisions

### Build NocoDB from a pinned upstream source derivation

The module will add `modules/packages/nocodb.nix`, building a pinned upstream source and locked JavaScript dependency graph as a Nix derivation. The systemd service will execute that derivation directly, rather than Docker, an opaque upstream binary, or a mutable npm install. This fits the repository's native-service preference and makes the source/version/content hash reviewable.

Alternatives considered:

- Docker/OCI image: upstream's common distribution route, but introduces an additional container runtime and weakens Nix closure transparency.
- Upstream binary: documented as suitable for quick testing and lacks the reviewable dependency behavior needed for a persistent service.
- Wait for nixpkgs packaging: leaves the requested service unavailable with no timeframe.

### Treat NocoDB control-plane resources as an ownership graph

The module will normalize declarations into a versioned desired-state document and reconcile in dependency order: administrator, users, managed tokens, workspace memberships, bases, base memberships, tables, fields, relations, views, and records. A versioned ledger maps stable declaration keys to NocoDB-generated IDs and stores only non-secret ownership metadata. Reconciliation first obtains an administrator session/API credential through supported APIs, then uses a version-pinned adapter for metadata, collaboration, token, and data operations.

Every managed resource has an explicit stable declaration key. Generated NocoDB IDs are implementation details, never declaration inputs. A resource missing from a declaration remains intact by default; deletion, field-type mutation, relation replacement, and managed-record deletion require the specific resource's explicit removal/destructive policy. The reconciler will never match unmanaged resources by display name alone.

Alternatives considered:

- SQL writes against the NocoDB metadata database: rejected because this bypasses NocoDB validation, migrations, permissions, and public compatibility contracts.
- Full authoritative reconciliation by name: rejected because it can adopt or delete user-created resources.
- Separate modules per resource: rejected initially because lifecycle, ordering, and shared ownership credentials are one service concern.

### Model bases, not duplicate projects

The public Nix model will use `bases`; runtime captures may report NocoDB's legacy project IDs only as provenance. A compatibility alias would create ambiguity around resource identity and deletion, so a `projects` declaration is rejected instead of silently mapped.

### Keep generated API tokens private and renewable

`services.osmium.nocodb.apiTokens.<name>` will reference a declared local user, stable token name, typed scope set, optional supported base restriction, a generated-secret output file, and an optional `rotation.triggerFile`. Token plaintext is available only at the declared private generated-secret path, never in Nix expressions or the ledger. Output paths are restricted to a NocoDB-owned protected credential directory or `/run`, use atomic `0600` writes, and are never printed.

The ledger records a randomly salted fingerprint of each minted token, not the value. If an output token file disappears, is unreadable, fails a live authorization probe, or the rotation trigger's salted fingerprint changes, the reconciler revokes the ownership-proven token, mints a replacement with the declared scopes/restrictions, validates it, atomically replaces the output file, and updates the ledger. If replacement validation fails, it retains the prior token/output when possible and reports failure. Scope identifiers are a closed set derived from the pinned NocoDB API contract; unsupported or duplicate scopes fail evaluation.

Alternatives considered:

- User-provided token secret files: rejected because NocoDB chooses token values and would make the declaration claim control it does not have.
- Persisting plaintext values in the ledger: rejected because ledgers are used for ownership/reporting and must remain secret-free.
- Silently recreating every token at boot: rejected because it invalidates consumers without a declared rotation event.

### Generate NocoDB runtime configuration atomically

The service will construct an `EnvironmentFile` in `/run` from fixed declarative values and runtime-only files. It will set `NC_DB`, `NC_AUTH_JWT_SECRET`, `NC_ADMIN_EMAIL`, `NC_ADMIN_PASSWORD`, `NC_APP_DATA_DIR`, a fixed port/listener, and hardened Community Edition defaults such as invite-only signup and disabled local-network import/webhook access unless explicitly supported later. PostgreSQL URL construction happens only in the root-owned generation unit, avoiding credentials in the store, unit text, or process arguments. The state directory, SQLite database, NocoDB application data, generated credentials, and ledger persist under the service-owned `/persistent` path.

### Fail closed at Community Edition boundaries

The Nix option schema will not expose organization, team, OIDC, SAML, SCIM, Keycloak, FreeIPA, identity-header, or licensed-only feature configuration. Explicitly attempting those unsupported attributes fails evaluation. The service will expose separate browser and machine API endpoints, but no gateway configuration: an authentication proxy alone cannot establish or map a NocoDB Community user session. A later licensed SSO change must assess native NocoDB OIDC first and add an independent browser-login check.

### Make reverse configuration runtime-derived and incomplete by default

`osmium-nocodb-observe` will call live supported APIs and normalize known state, ledger ownership, API version, completeness, and provenance. `osmium-nocodb-candidate` will convert only that observation into review-only Nix candidate data. It will preserve supported non-secret configuration; unresolved passwords, administrator credentials, generated token values/output paths, PostgreSQL credentials, attachment sources, and unknown/enterprise fields yield explicit findings and `complete = false`, never invented defaults. Neither tool writes to NocoDB, declarations, runtime secret files, or the ledger.

## Risks / Trade-offs

- [NocoDB upstream API and scope identifiers can change] → Pin the source/API adapter version, validate scopes against that contract, and fail upgrades that lack an adapter update.
- [Building NocoDB's JavaScript dependency tree can be expensive or fragile] → Use a fixed source revision and lockfile/dependency hash; make the package build a dedicated flake check before service tests.
- [Some Community Edition UI state lacks a stable public management API] → Represent only documented, API-observable state; reject or report unsupported state rather than scraping the UI or accessing metadata SQL.
- [A generated token output file can be lost] → Probe output/token usability and perform explicit managed replacement, preserving the old token whenever replacement validation fails.
- [PostgreSQL availability and migrations increase operational risk] → Keep SQLite as the default; make PostgreSQL opt-in with endpoint validation, readiness ordering, and a dedicated live MicroVM check.
- [Local NocoDB identities duplicate Keycloak/FreeIPA identities] → Reject federation declarations and document the Community Edition boundary rather than creating unsynchronized shadow identity behavior.

## Migration Plan

1. Build the pinned package and add the disabled-by-default module; no existing service is modified.
2. Deploy a new MicroVM with SQLite, runtime JWT/admin files, and an empty persistent state directory. Verify one-time bootstrap before declaring other resources.
3. Add users, API tokens, memberships, and bases incrementally. Start all resource policies in preserve mode; enable destructive policy only after reviewing ownership-ledger entries and a backup.
4. For PostgreSQL, provision the database and runtime password first, stop the SQLite instance, migrate only through an explicit documented export/import procedure, and enable the PostgreSQL declaration. Automatic backend migration is not performed.
5. Roll back module configuration by stopping the service and retaining its persistent directory/database. Re-enable the prior configuration to restore behavior; do not delete the state directory, revoke generated tokens, or modify Keycloak/FreeIPA automatically.
