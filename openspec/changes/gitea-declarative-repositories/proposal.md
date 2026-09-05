## Why

The Mythoclast Gitea module can declaratively provision users and
organizations, but repositories are still created and configured manually.
That leaves repository ownership, visibility, metadata, and lifecycle outside
the reproducible service definition and makes a complete Gitea deployment
difficult to recreate.

## What Changes

- Add a `repositories` declaration to the Mythoclast Gitea service for
  repositories owned by declared users or organizations.
- Provision repositories idempotently after their owners exist, applying the
  supported repository metadata without changing stable repository identity.
- Define explicit behavior for existing repositories, owner changes, invalid
  declarations, and removal of declarations; default reconciliation remains
  non-destructive.
- Keep repository contents, Git history, LFS objects, hooks, deploy keys, and
  collaborators outside this initial metadata provisioning scope unless they
  are explicitly represented as supported attributes.
- Add drift detection for declared repository attributes and a review-only
  conversion from observed drift into Mythoclast repository declarations.
- Add live-system capture of repository attributes and a review-only conversion
  into Mythoclast repository declarations.
- Ensure both reverse-configuration directions are secret-safe, provenance-aware,
  explicit about unsupported or ambiguous state, and unable to claim
  completeness when required data is unavailable.
- Add dedicated MicroVM integration tests for drift-based conversion and
  live-capture conversion, each exercising the running Gitea service and using
  runtime-generated observations rather than equivalent hand-authored fixtures.

## Capabilities

### New Capabilities

- `gitea-declarative-repositories`: Declarative repository ownership and
  metadata provisioning, repository drift reverse-configuration, and live
  capture reverse-configuration.

### Modified Capabilities

- None.

## Impact

- Extends `modules/services/gitea.nix` with repository options and runtime
  reconciliation.
- Extends Gitea drift/export tooling and adds live capture output for repository
  records.
- Adds validation and MicroVM test coverage for user-owned and
  organization-owned repositories.
- Uses existing runtime Gitea credentials and API lifecycle; it does not embed
  passwords, tokens, or repository data in evaluated Nix configuration.
