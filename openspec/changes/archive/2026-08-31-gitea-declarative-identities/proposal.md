## Why

The Gitea service currently provisions only its initial administrator. Guests
that depend on known users or organizations still require imperative setup,
which makes deployments non-reproducible and makes the identity state harder
to verify after an impermanent guest reboot.

## What Changes

- Add declarative definitions for non-administrator Gitea users, including
  usernames, email addresses, and runtime password files.
- Add declarative definitions for organizations, including owner references,
  names, descriptions, and visibility.
- Reconcile missing users and organizations after Gitea is available and during
  configuration activation, without duplicating existing records.
- Ensure declarative users are created without administrator privileges and do
  not grant administrator access through organization provisioning.
- Rotate a declarative user's password when its configured secret-file value
  changes, using the same runtime-only secret guarantees as administrator
  rotation.
- Preserve existing records when declarations are removed; deletion and
  destructive ownership changes require explicit future support.
- Add MicroVM coverage for user login, organization ownership and access,
  idempotent restart behavior, and changed-secret rotation.
- Document the declarative identity configuration and lifecycle semantics.

## Capabilities

### New Capabilities

- `gitea-declarative-identities`: Declarative provisioning and reconciliation of
  non-admin users and organizations.

### Modified Capabilities

- None.

## Impact

- Extends `modules/services/gitea.nix` with user and organization options and a
  persistent reconciliation workflow.
- Extends `tests/gitea.nix` with identity and organization integration tests.
- Updates README configuration and lifecycle documentation.
- Reuses the existing Gitea package, state persistence, and SOPS-compatible
  runtime secret-file pattern without adding a new dependency.
