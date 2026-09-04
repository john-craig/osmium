## Why

The current Gitea module reconciles declared identities but cannot report
out-of-band changes. Operators need a trustworthy, read-only view of missing,
changed, unmanaged, and conflicting Gitea identities before deciding whether
to alter configuration or adopt state.

## What Changes

- Add read-only inspection of users and organizations from the running Gitea instance.
- Normalize observed fields and compare them with the declarative identity configuration.
- Classify drift, including missing, changed, unmanaged, administrator, and ownership conflicts.
- Add human-readable and machine-readable reports with stable exit behavior for automation.
- Add optional startup/activation or timer-driven checks without changing Gitea state.
- Persist only sanitized observation metadata and fingerprints when persistence is enabled.
- Add MicroVM coverage for detection, classification, API failures, pagination, and read-only behavior.

## Capabilities

### New Capabilities

- `gitea-drift-detection`: Read-only observation and classification of Gitea identity drift.

### Modified Capabilities

- None.

## Impact

- Extends the Gitea module with inspection configuration and a read-only reporting workflow.
- May add a small runtime helper using the pinned Gitea API and `jq`.
- Extends `tests/gitea.nix` with external mutation and drift-reporting scenarios.
- Updates README documentation and the Gitea operational model.
- Does not alter existing reconciliation or destructive lifecycle behavior.
