## Context

The existing module has additive reconciliation for declared users and
organizations in `modules/services/gitea.nix`, backed by a persistent Gitea
state directory and a MicroVM test. Gitea's administrative API can list users
and organizations, but standard webhooks are primarily repository-activity
notifications and are not sufficient as the sole identity-drift source.

## Goals / Non-Goals

**Goals:**

- Establish a normalized observed-state model shared with later export tooling.
- Make inspection strictly read-only and safe to run from systemd or manually.
- Distinguish configuration drift from operational/API failure.
- Support complete pagination, deterministic output, and sanitized persistent history.

**Non-Goals:**

- Automatically changing Gitea records in response to drift.
- Automatically changing or committing Nix source files.
- Inferring passwords, secret paths, causal actors, or intended ownership.
- Depending on Gitea Enterprise audit logs or webhook delivery for correctness.

## Decisions

### Use a snapshot collector as the source of truth

The implementation will query the pinned Gitea administrative API and normalize
the complete paginated result. This is preferred over database reads because it
respects Gitea's public contract and works across supported database backends.
Webhooks may later reduce detection latency, but periodic snapshots remain the
correctness fallback for missed deliveries and identity mutations.

### Compare an explicit field allowlist

The comparator will define the supported fields for users and organizations and
ignore all credentials and volatile fields. This avoids false drift from API
implementation details and prevents secrets from entering reports or state.

### Keep desired-state comparison separate from history comparison

The report will compare the snapshot with current declarations first. A
persistent fingerprint will only indicate that observed state changed since the
last inspection. This prevents an old snapshot from being mistaken for desired
state and avoids coupling read-only detection to mutation authorization.

### Expose one-shot reporting with an optional timer

The core inspector will be callable as a oneshot command. NixOS configuration
may optionally schedule it with systemd. The default behavior will not fail
normal service startup because drift is informational; explicit check mode will
return nonzero for monitoring and CI.

### Treat conflicts as safety failures

Administrator and ownership conflicts will be surfaced distinctly. The
inspector will never suggest demotion, ownership transfer, deletion, or an
unreviewed correction. This is necessary because the current reconciliation
contract is intentionally non-destructive.

## Risks / Trade-offs

- [Risk] API output can change between Gitea versions. -> Mitigation: pin the package, normalize only documented fields, and test the pinned version in the MicroVM.
- [Risk] A partial API failure could look like deletion or missing state. -> Mitigation: fail the whole collection and never classify missing records from an incomplete snapshot.
- [Risk] Fingerprints could leak equality information. -> Mitigation: use a keyed or salted digest over sanitized canonical JSON and restrict state permissions.
- [Risk] Polling detects changes later than events. -> Mitigation: allow an optional webhook trigger later while retaining periodic full snapshots.
- [Risk] Reports may expose private profile metadata. -> Mitigation: define the output allowlist and provide configurable redaction before writing persistent reports.

## Migration Plan

Add the inspector disabled by default, then enable a read-only timer for an
existing deployment. Existing reconciliation continues unchanged. Operators can
use reports to identify drift before deciding whether to edit declarations or
use the separate reverse-configuration workflow.
