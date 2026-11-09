## Why

Osmium has no native Homebox service module, leaving household inventory and organization data outside the declarative deployment model. Homebox provides native OIDC, a REST API, and a collection-scoped inventory model, but its supported API does not provide complete administrator identity management, so a bounded runtime database bootstrap path is needed for declarative users, groups, membership, and API keys.

## What Changes

- Add a native Homebox service using the packaged Homebox application, persistent storage, and the standard Osmium MicroVM lifecycle.
- Configure Homebox's native OIDC integration with runtime-only client secrets; do not add a Keycloak gateway because Homebox supports the required browser OIDC flow natively.
- Add declarative management for collection-scoped tags, entity types, entity templates, and template fields.
- Add a narrowly scoped runtime bootstrap helper for users, groups, group membership, and user-owned API keys where Homebox's supported REST API is insufficient.
- Treat Homebox's database schema as a versioned implementation boundary with migration/version checks and fail-closed behavior on unsupported versions.
- Keep passwords, OIDC client secrets, session tokens, API keys, invitations, and other credentials out of the Nix store, logs, and reverse-configuration output.
- Preserve unmanaged records and avoid automatic deletion unless ownership and dependency safety are proven.
- Exclude inventory entity records, attachments, maintenance history, imports/exports, duplicate actions, notifiers, and destructive bulk actions from the initial declarative scope.
- Add review-only drift detection and live capture for supported identities and collection metadata, with explicit provenance, ownership, unsupported-state, and completeness reporting.
- Add booted MicroVM integration tests for service behavior, persistence, OIDC boundary configuration, identity bootstrap, API-key lifecycle, metadata reconciliation, drift conversion, and live capture.

## Capabilities

### New Capabilities

- `homebox-service`: Homebox lifecycle, persistence, networking, native OIDC, and MicroVM behavior.
- `homebox-declarative-identities`: Users, groups, membership, runtime credentials, and API-key lifecycle using the hybrid API/database boundary.
- `homebox-declarative-metadata`: Collection-scoped tags, entity types, entity templates, and template fields.
- `homebox-reverse-configuration`: Review-only drift and live capture for supported Homebox state.

### Modified Capabilities

<!-- No existing capability requirements are changed. -->

## Impact

- Affected implementation areas: `modules/default.nix`, a new `modules/services/homebox.nix`, MicroVM definitions in `flake.nix`, and Homebox integration checks.
- Runtime dependency: the nixpkgs Homebox package and its database/storage/runtime dependencies.
- Supported REST API integration: groups, tags, entity types, templates, current-user APIs, and API-key endpoints.
- Runtime database integration: version-aware user, group, membership, and API-key bootstrap where supported API operations cannot express the desired state.
- Persistent application/database and attachment storage must survive MicroVM replacement, while credentials remain runtime-only.
- Reverse configuration must remain non-mutating, secret-safe, provenance-aware, and incomplete when required state cannot be represented.
