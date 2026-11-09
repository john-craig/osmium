## Why

Osmium needs a persistent, impermanent-MicroVM-friendly Paperless-ngx service for document ingestion and retrieval. NixOS already packages Paperless-ngx and exposes its core service configuration, but Osmium still needs a service boundary, persistence contract, local user reconciliation, and protected API-token delivery.

## What Changes

- Add an Osmium Paperless-ngx service module backed by the existing nixpkgs package and `services.paperless` module.
- Configure persistent Paperless data, media, consumption, export, search-index, SQLite database, and broker state across guest-root recreation, with optional PostgreSQL support through the native NixOS module.
- Add runtime-only secret handling for the Paperless secret key, administrator bootstrap password, database credentials, broker credentials, and other environment-file settings.
- Add declarative local Paperless users with stable usernames, email, active/staff/superuser state, password files, and supported group membership/permissions.
- Add declarative per-user API-token provisioning with protected generated-token output and explicit ownership, replacement, and removal behavior.
- Preserve Paperless token semantics: tokens have no independent scopes; access is controlled by the owning Paperless user’s global/object permissions.
- Add review-only drift detection and live capture for supported Paperless users, groups, permissions, and token metadata without exporting passwords or token values.
- Assess native Paperless OIDC support and keep external identity integration out of this change; a future Keycloak/FreeIPA integration SHALL use Paperless’s native OIDC/allauth support rather than an identity-header gateway.
- Add booting MicroVM checks for lifecycle, document consumption, persistence, local users, API-token authorization/rotation, secret handling, drift conversion, and live capture.

## Capabilities

### New Capabilities
- `paperless-service`: Runs Paperless-ngx as a persistent Osmium MicroVM service with SQLite by default and native backend/broker configuration support.
- `paperless-declarative-identities`: Reconciles local Paperless users, groups/permissions, and one managed API token per declared user with protected token delivery.
- `paperless-reverse-configuration`: Provides safe, review-only drift detection and live capture for supported Paperless identity and token metadata.

### Modified Capabilities
- None.

## Impact

- Adds `modules/services/paperless.nix`, module imports, documentation, Paperless MicroVM tests, reverse-configuration tools, and flake checks.
- Reuses `pkgs.paperless-ngx`, `services.paperless`, `paperless-manage`, local SQLite, and the native Redis/PostgreSQL integration instead of introducing a custom application package.
- Adds persistent storage for Paperless data/media/consume/export/index state and protects generated API-token files from the Nix store.
- Uses Paperless REST APIs for observation and authorization, plus a pinned-version management adapter for creating/revoking tokens for users other than the bootstrap administrator when the public API cannot perform that operation.
- Does not add Keycloak, FreeIPA, SCIM, remote-user headers, or proxy-authentication configuration. Native Paperless OIDC support is documented as the required basis for a future identity integration.
