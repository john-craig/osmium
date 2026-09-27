## Why

Osmium needs a native, impermanent-friendly Vaultwarden service for encrypted
personal and organization password vaults. Vaultwarden is intentionally exempt
from the shared Keycloak SSO gateway: Bitwarden-compatible clients and vault
encryption depend on Vaultwarden's native account, master-key, and encrypted
sync protocol, so a browser gateway would not provide equivalent authentication
or vault access.

## What Changes

- Add a disabled-by-default `services.osmium.vaultwarden` module using the
  pinned Nixpkgs Vaultwarden package, explicit guest/host networking, persistence,
  readiness, and runtime-only administrative inputs.
- Add runtime-safe declarative provisioning for Vaultwarden users, with optional
  master-password files and rotation when a protected file changes. User-vault
  item provisioning remains explicitly out of scope.
- Add declarative organization provisioning, including organization metadata,
  collections, pre-encrypted organization cipher payloads, and membership of
  provisioned users with explicit roles and access.
- Add secret-safe non-secret desired-state and ownership ledgers with ordered,
  idempotent reconciliation, safe update/removal policies, and failure
  preservation.
- Add drift and live-capture reverse configuration for supported Vaultwarden
  declarations, with provenance, incomplete-state reporting, unresolved runtime
  secret references, and no plaintext or encrypted vault-secret leakage.
- Add booting MicroVM integration checks for service lifecycle, user and
  organization provisioning, encrypted organization-vault replay, membership,
  password rotation, persistence, failure handling, and the explicit no-SSO
  boundary.
- Document the Vaultwarden Keycloak exemption, native client authentication
  boundary, runtime secret deployment, encrypted-payload contract, and recovery
  behavior.

## Capabilities

### New Capabilities

- `vaultwarden-service`: Native Vaultwarden service lifecycle, networking,
  persistence, runtime credentials, and the documented Keycloak SSO exemption.
- `vaultwarden-declarative-provisioning`: Declarative users, optional rotating
  master passwords, organizations, collections, encrypted organization ciphers,
  memberships, and safe reconciliation.
- `vaultwarden-reverse-configuration`: Review-only drift detection and live
  capture for supported Vaultwarden state.

### Modified Capabilities

- None.

## Impact

- New module: `modules/services/vaultwarden.nix` and module import wiring.
- New MicroVM checks and flake outputs covering service, provisioning, drift,
  live capture, and the no-SSO boundary.
- New documentation under `docs/vaultwarden.md`.
- Runtime dependency on Vaultwarden's Bitwarden-compatible HTTP and identity
  APIs. The reconciler must use supported APIs and reject unsupported or
  ambiguous encrypted-vault states rather than mutating the database directly.
