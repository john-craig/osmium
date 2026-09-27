## Why

Osmium has no native Grocy service module, leaving household inventory and planning data outside the declarative deployment model. Adding Grocy with persistent state, declarative identities, and a small set of stable reference entities provides a reproducible service boundary without replaying transactional household activity.

## What Changes

- Add a native NixOS Grocy module using the packaged `grocy` application.
- Run Grocy in the standard Osmium MicroVM service model with persistent application data and explicit network exposure.
- Add declarative Grocy users with ownership-safe reconciliation and runtime-only password handling.
- Add one runtime-generated API token per declared user, with protected secret-file output and changed-secret rotation where supported.
- Add declarative management for Grocy locations, quantity units, quantity-unit conversions, product groups, and shopping locations.
- Preserve unmanaged Grocy records and exclude destructive deletion by default.
- Exclude products, barcodes, recipes, recipe positions, chore/task definitions, stock, shopping-list contents, execution history, and other operational transactions from declarative management.
- Add review-only drift detection and live-system capture for supported users and reference entities, with explicit incomplete results for secrets, ambiguity, unsupported fields, and unmanaged state.
- Add MicroVM integration tests covering service behavior, persistence, identity/token bootstrap and rotation, reference-data reconciliation, drift conversion, and live capture.

## Capabilities

### New Capabilities

- `grocy-service`: Grocy service lifecycle, persistence, networking, and MicroVM integration behavior.
- `grocy-declarative-identities`: Declarative users, runtime-only credentials, API-token bootstrap, ownership, and rotation.
- `grocy-declarative-reference-data`: Declarative locations, quantity units, conversions, product groups, and shopping locations.
- `grocy-reverse-configuration`: Review-only drift and live-capture conversion for supported Grocy declarations.

### Modified Capabilities

<!-- No existing capability requirements are changed. -->

## Impact

- Affected implementation areas: `modules/default.nix`, a new `modules/services/grocy.nix`, MicroVM definitions in `flake.nix`, and service-specific integration tests.
- Runtime dependency: the nixpkgs `grocy` package and its PHP/web runtime dependencies.
- Grocy API integration: users, permissions, API keys, and generic reference-entity CRUD endpoints.
- Persistent state must survive MicroVM replacement while credentials remain runtime-only and are not embedded in the Nix store.
- Reverse configuration must be non-mutating, secret-safe, provenance-aware, and must not claim completeness when required state cannot be represented.
