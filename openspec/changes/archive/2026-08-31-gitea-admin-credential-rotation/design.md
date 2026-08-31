## Context

The existing module creates the administrator once with a runtime
`passwordFile` and persists a completion marker beneath Gitea's `stateDir`.
See `proposal.md` and the delta requirements for the intended behavior.

## Goals / Non-Goals

**Goals:**

- Make credential age observable and rotation repeatable without making normal
  service restarts rotate credentials.
- Ensure a failed or delayed rotation cannot remove the last known-good access.
- Keep plaintext credentials transient and compatible with SOPS-managed files.
- Make expiration and recovery behavior executable in the Gitea MicroVM test.

**Non-Goals:**

- Generating replacement credentials automatically inside the guest.
- Rotating non-administrator users, API tokens, SSH keys, or OAuth credentials.
- Disabling the administrator solely because its age deadline passed.
- Supporting multiple administrators or quorum-based rotation in this change.

## Decisions

### Use an explicit replacement secret file

The module will accept a runtime replacement password path, allowing operators
to update a SOPS secret and activate the change without placing the password in
Nix. Automatic in-guest password generation was rejected because the resulting
credential still needs a secure delivery path to operators and the service's
clients.

### Use activation-triggered rotation plus a periodic systemd check

A dedicated oneshot service will be triggered by configuration activation when
the replacement identity changes, and a timer will check age after Gitea is
available. Activation provides prompt rotation for deliberate secret updates;
the timer handles expiration and retries when activation or the secret backend
was temporarily unavailable.

The state file will contain the last successful rotation timestamp and a
one-way digest of the applied credential, with restrictive ownership and mode.
The completion marker from initial bootstrap remains separate so existing
bootstrap semantics are preserved.

The timer remains necessary because secret files may be refreshed independently
of a host rebuild. It also makes expiration and retry behavior deterministic
after a transient secret or Gitea failure.

### Treat expiration as a deadline, not immediate account invalidation

When the deadline passes without a replacement, the current password remains
valid and the service fails visibly and retries. Disabling the account before
success was rejected because it can lock out the only administrator. Operators
must provide a new secret before rotation can complete.

### Require a changed replacement before applying it

The workflow will compare a non-reversible digest of the runtime replacement
against the persisted applied digest. It will not issue a redundant change for
an unchanged secret. The digest algorithm and metadata format are internal and
may change without affecting the behavioral contract.

### Test with controlled deadlines and runtime fixtures

The MicroVM test will use a short test-only maximum age and guest-local fixture
files to exercise initial success, expired rotation, restart persistence, and
missing-secret recovery. Production defaults will avoid unexpectedly frequent
rotation.

## Risks / Trade-offs

- [Risk] A secret refresh may not be visible until the next timer check. ->
  [Mitigation] Make the interval configurable and document the retry/check
  behavior.
- [Risk] A digest stored in state can reveal whether two passwords are equal. ->
  [Mitigation] Store only a salted, non-reversible digest with a local salt and
  never store plaintext; equality leakage is limited to the guest's persisted
  metadata.
- [Risk] The expiration deadline can pass while operators are unavailable. ->
  [Mitigation] Preserve the last known-good credential, fail visibly, and retry
  until a replacement is supplied.
- [Risk] Gitea CLI/API behavior may differ across pinned versions. ->
  [Mitigation] Exercise the exact pinned package in the MicroVM integration
  test rather than relying only on option evaluation.

## Migration Plan

Enable rotation only after the existing bootstrap administrator is confirmed
usable. Provide the replacement secret, deploy the configuration, and monitor
the rotation service and journal. Disabling rotation leaves the last applied
credential unchanged and removes only future scheduled checks; it does not
revert a completed rotation.
