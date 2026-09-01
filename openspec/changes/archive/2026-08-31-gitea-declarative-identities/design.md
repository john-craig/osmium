## Context

The existing Gitea module has persistent service state, one-time administrator
bootstrap, and administrator password rotation. This change adds identities
that depend on the same service lifecycle while avoiding destructive drift
correction.

## Goals / Non-Goals

**Goals:**

- Provision a small, explicitly declared set of users and organizations
  repeatably.
- Make user and organization creation safe across activation, startup, and
  impermanent guest restarts.
- Keep user passwords runtime-only and rotate them when secret values change.
- Make ownership and non-admin behavior observable in the MicroVM test.

**Non-Goals:**

- Declarative repository, team, webhook, deploy-key, or access-token
  provisioning.
- Deleting or transferring records when declarations are removed.
- Demoting pre-existing administrators or taking ownership of externally
  managed organizations.
- Supporting external identity providers or LDAP synchronization.

## Decisions

### Use structured attrsets keyed by stable local names

Users and organizations will be represented as attrsets keyed by local
declaration names, with explicit `username` or `name` fields used as the
service identity. This permits validation of duplicate references and stable
owner relationships without treating Nix attrset keys as Gitea usernames.

### Reconcile through a dedicated service

A dedicated reconciliation oneshot will run after Gitea and after the admin
bootstrap when enabled. It will be wanted at multi-user startup and invoked by
configuration activation. Each run will query or inspect existing records,
create missing records, and update only supported metadata. The workflow will
write persistent completion/fingerprint state only after each operation
succeeds.

### Preserve records that leave the declaration

The reconciler will be additive and corrective only for declared records. It
will not delete or transfer identities because removing a declaration can be
an accidental configuration change and Gitea records may be shared with other
systems. Explicit destructive lifecycle support can be added later.

### Keep organization ownership explicit and ordered

An organization owner must reference a declared user. Reconciliation will
provision users before organizations and fail rather than choose an implicit or
administrator owner. Organization creation will not request administrator
privileges for the owner.

### Use per-user runtime secret fingerprints

Each declared user's password file will be read only by the runtime
reconciler. A per-user salted, non-reversible fingerprint and last-success
metadata will be persisted beneath the Gitea state directory. A changed
fingerprint triggers password replacement during activation; the same
reconciler also retries failed changes and remains safe to invoke repeatedly.

### Prefer the pinned Gitea administrative interface

The implementation will use the exact administrative CLI/API available in the
pinned Gitea package, with command failures treated as failed reconciliation.
The MicroVM test will exercise the pinned version rather than mocking identity
operations.

## Risks / Trade-offs

- [Risk] Updating user metadata may overwrite out-of-band changes. ->
  [Mitigation] Limit reconciliation to explicitly declared fields and document
  ownership of those fields.
- [Risk] Additive-only reconciliation leaves removed identities behind. ->
  [Mitigation] Make this non-destructive behavior explicit and defer deletion to
  a separately reviewed feature.
- [Risk] A failed rotation can leave the old fingerprint and secret out of
  sync. -> [Mitigation] Commit metadata only after Gitea succeeds and retry on
  later activation/startup.
- [Risk] Secret fingerprints reveal equality for a given local salt. ->
  [Mitigation] Use per-user persistent salts, store no plaintext, and restrict
  metadata ownership and mode.

## Migration Plan

Existing administrator bootstrap and rotation remain unchanged. Operators can
add user declarations one at a time with runtime password files, then add
organizations referencing those users. Removing declarations does not remove
the provisioned records, so rollback is configuration-only and non-destructive.
