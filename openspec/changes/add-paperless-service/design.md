## Context

See `proposal.md` for motivation. nixpkgs already provides `paperless-ngx` and a native `services.paperless` module with SQLite defaults, optional local PostgreSQL, Redis-compatible broker support, `paperless-manage`, data/media/consume/export directories, and a runtime `environmentFile`. Osmium service modules add MicroVM forwarding, impermanence, service ordering, runtime secret handling, ownership ledgers, and live checks.

Paperless exposes a versioned REST API, including `/api/users/`, `/api/token/`, profile and permission endpoints. Its API tokens are Django REST Framework user tokens: one token belongs to a user and inherits that user’s permissions; Paperless does not provide independent token scopes. The public token endpoint can authenticate a user and obtain a token, but token replacement for an arbitrary managed user may require a version-pinned Django management/ORM adapter.

Paperless also supports native OIDC through django-allauth. This change does not configure it, but the future integration boundary must use that native mechanism rather than trusting a remote-user header or injecting identity through a proxy.

## Goals / Non-Goals

**Goals:**

- Wrap the native Paperless NixOS service with Osmium persistence, networking, secret, and MicroVM guarantees.
- Reconcile local users and supported groups/permissions without adopting unmanaged identities.
- Deliver one ownership-proven API token per declared user through protected runtime output files.
- Make token limitations explicit: no independent scopes; authorization follows the user.
- Verify document ingestion/search, user authentication, token authorization, rotation, persistence, and reverse configuration in live MicroVMs.

**Non-Goals:**

- Manage documents, tags, correspondents, workflows, mail rules, storage paths, OCR models, or object-level document permissions declaratively in this initial service change.
- Provide OIDC, SAML, SCIM, FreeIPA, Keycloak, remote-user header, or proxy-authentication configuration.
- Create a second Paperless configuration language or replace the upstream NixOS module.
- Claim token scope isolation that Paperless cannot enforce.

## Decisions

### Delegate runtime configuration to the native Paperless module

`services.osmium.paperless` will compose or expose the upstream options and set Osmium-specific defaults for state paths, service ownership, ports, persistence, and readiness. The module will retain `services.paperless.settings`, `environmentFile`, `passwordFile`, database, broker, OCR, Tika/Gotenberg, and exporter behavior instead of duplicating Paperless settings.

Alternatives considered:

- A custom Paperless package/service: rejected because nixpkgs already provides a maintained package and native module.
- A container-based deployment: rejected because it adds an unnecessary runtime boundary in this native NixOS repository.

### Persist the complete Paperless document state graph

The module will persist `dataDir`, `mediaDir`, `consumptionDir`, and `exporter.directory` when enabled, with ownership and permissions matching the Paperless service account. SQLite remains the native default; PostgreSQL and a Redis-compatible broker are explicit options with runtime credential files and service dependencies. The module will not persist arbitrary externally mounted document directories unless they are explicitly declared inputs.

### Reconcile users through supported APIs and a pinned adapter

User and group metadata will be normalized into a desired document and reconciled in dependency order: bootstrap administrator, groups, users, memberships, global permissions, then token outputs. REST endpoints are preferred for user/group/permission state. Token creation/replacement uses a version-pinned adapter: it may obtain a token through `/api/token/` for a managed user and may use `paperless-manage`/Django’s token model only for the operation Paperless does not expose publicly. The adapter must assert the installed package/version and fail closed if its model or command contract changes.

The ledger stores declaration keys, Paperless IDs, non-secret metadata, ownership proof, token presence/output metadata, and salted fingerprints where needed for change detection. It never stores passwords, token values, password hashes, or reversible digests.

### Model one API token per user, without scopes

Each token declaration identifies one managed user and one protected output. The service validates that the requested user is declared and that no unsupported `scopes` field is present. Effective authorization is tested through the user’s actual Paperless permissions. Rotation is explicit: delete/revoke only the ledger-proven managed token, create a replacement, authenticate a harmless API request, atomically replace the output, and update the ledger. If the replacement fails, retain the previous token/output when still usable and report failure.

Alternatives considered:

- One shared administrator token: rejected because it violates least privilege and user attribution.
- Pretend scopes are supported: rejected because Paperless DRF tokens have no independent scope mechanism.
- Manage all token rows by raw database writes: rejected except for the narrowly isolated pinned token adapter, because general raw database mutation bypasses Django/Paperless behavior.

### Use explicit runtime secret and identity boundaries

The module will require a stable `PAPERLESS_SECRET_KEY` runtime file and disable account signup and remote-user authentication by default. It will not configure Keycloak/FreeIPA. The design records that Paperless has native OIDC; a future SSO change must configure and test that native OIDC path, including browser login and local API-token behavior, rather than enabling `PAPERLESS_ENABLE_HTTP_REMOTE_USER_API`.

### Reverse configuration is observation-derived and secret-safe

Observation will use versioned API endpoints and ownership metadata. It will report local users, groups, permissions, token presence, and token ownership but never read/export token values or passwords. Captured users require operator-provided password-file references, and captured tokens require operator-selected output paths. Unobservable object-level document state and unsupported fields remain explicit incomplete findings rather than being silently omitted.

## Risks / Trade-offs

- [Paperless user/token APIs and Django token internals can change between package versions] → Pin nixpkgs/package compatibility, expose an adapter version check, and fail before mutation when the contract is not recognized.
- [A token is as powerful as its user and cannot have independent scopes] → Require separate least-privilege users, reject scope declarations, and test both allowed and denied operations through actual Paperless permissions.
- [Deleting a managed user may affect document ownership] → Preserve documents by default, require explicit user-removal policy, and refuse deletion when ownership consequences are not represented.
- [OCR and document processing are resource-intensive] → Keep OCR settings upstream-configurable, allocate adequate MicroVM resources, and use a small deterministic fixture document in checks.
- [Database/broker state can become inconsistent if mutated externally] → Document stop-before-migration/restore behavior and never modify the Paperless database directly outside the token adapter.

## Migration Plan

1. Enable the new service with the existing Paperless package/module and a fresh persistent state directory; provide secret key, administrator, and broker runtime files.
2. Verify the Paperless health endpoint and consume/search a fixture document before changing ingress or scanner paths.
3. Declare local users and token outputs incrementally. Start with preserve-only removal policy and review ownership ledger results.
4. For an existing deployment, stop Paperless, copy data/media/consume/export state with ownership preserved, retain the existing secret key, and migrate the database only through the documented Paperless/NixOS procedure. Do not auto-convert SQLite to PostgreSQL.
5. Roll back by stopping the Osmium service and restoring the prior Paperless process/configuration and persistent directories. Do not revoke unmanaged tokens or delete documents automatically.
