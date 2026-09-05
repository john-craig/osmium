## Context

The repository currently uses `mythoclast` as both a product brand and a
runtime namespace. The string appears in NixOS options, systemd units, command
names, Python schema identifiers, persistence paths/markers, tests, examples,
documentation, and OpenSpec artifacts. Existing Gitea and filesystem snapshot
state can be persistent and must not be treated as disposable during a rename.

## Goals / Non-Goals

**Goals:**

- Establish Osmium as the single canonical name for new interfaces and output.
- Preserve existing service data and one-time lifecycle markers during upgrade.
- Make compatibility explicit and prevent duplicate old/new runtime ownership.
- Verify fresh and migrated deployments in MicroVMs.
- Retain historical OpenSpec and Git provenance without rewriting history.

**Non-Goals:**

- Changing service functionality, data models, security posture, or deployment
  semantics unrelated to naming.
- Rewriting archived OpenSpec changes or historical commits.
- Renaming the on-disk checkout directory as part of the implementation; that
  is an operator/repository-hosting concern separate from runtime identity.
- Supporting indefinite compatibility with every old command or option.

## Decisions

### Separate canonical names from historical names

All active implementation and documentation will use `osmium`. Archived
changes and Git history remain unchanged. A checked-in compatibility inventory
will document each remaining `mythoclast` occurrence so the audit can
distinguish migration code from accidental stale branding.

### Use explicit migration for persisted state

Migration will inspect known old paths and markers, validate expected state,
copy or rename atomically as appropriate, and write a completion marker only
after the new state is complete. It will preserve the old state until the new
state is verified and will be idempotent. State migrations must never copy
secret contents into logs or generated configuration.

### Prefer bounded compatibility aliases

Where NixOS and systemd permit it without duplicate ownership, old option/unit/
command names will be compatibility aliases that route to Osmium. Aliases will
have a documented removal boundary and emit migration guidance. Where aliasing
would create evaluation ambiguity or duplicate units, the old interface will
fail with an actionable error instead.

### Rename schema identities deliberately

New schema identifiers will use `osmium`. Readers may accept the previous
schema namespace only for a bounded migration period and must normalize it to
the Osmium schema before writing new artifacts. Existing persisted records will
be versioned and migrated rather than blindly string-replaced.

### Verify behavior, not just text replacement

The test plan will include a fresh Osmium MicroVM and a migration MicroVM with
pre-seeded Mythoclast-era state. A source naming audit and focused unit tests
will supplement, but not replace, runtime tests of Gitea, snapshot tooling,
systemd lifecycle, persistence, and conflict behavior.

## Risks / Trade-offs

- [Risk] A missed namespace leaves mixed active branding → use a repository-wide
  audit with an explicit historical/compatibility allowlist.
- [Risk] Renaming a persistence path loses service state → migrate atomically,
  retain the source until verification, and test recreation/restart in a VM.
- [Risk] Old and new units run simultaneously → route aliases to canonical
  units and add conflict assertions and runtime checks.
- [Risk] Schema renaming breaks existing artifacts → support bounded read-time
  normalization and preserve schema version/provenance.
- [Risk] A compatibility layer prolongs migration complexity → document its
  scope and removal release while keeping new output canonical.
- [Risk] Broad replacement changes historical meaning → exclude archived
  artifacts and Git history from automated active-source rewrites.

## Migration Plan

1. Inventory all active and historical occurrences and define the compatibility
   allowlist.
2. Introduce Osmium canonical identifiers and migration helpers while retaining
   bounded old-interface recognition.
3. Migrate persisted service state and verify it before switching authoritative
   paths or markers.
4. Update active configurations, examples, tests, documentation, and flake
   outputs to Osmium.
5. Run fresh and migrated MicroVM checks, then remove compatibility only in a
   separately announced breaking release if desired.

## Open Questions

- The exact compatibility window for old Nix option and command names can be
  selected during implementation without changing the canonical Osmium or
  migration requirements.
