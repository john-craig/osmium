## Context

The existing Gitea module reconciles users and organizations through a runtime
administrator path, persists non-reversible state under the Gitea state
directory, and exposes secret-free drift/export tooling. This change adds
credentials whose values are intentionally available only at creation time, so
identity tracking and secret delivery must be separate concerns. See
`proposal.md` and the credential specification for the observable contract.

## Goals / Non-Goals

**Goals:**

- Use stable declarations to create exactly one identifiable managed credential
  per intended Gitea resource.
- Deliver one-time secret values to protected, explicitly configured files.
- Reuse credentials across restarts and revoke only credentials proven to be
  managed by the declaration.
- Normalize credential metadata for both drift conversion and live capture.
- Make missing secrets, unsupported Gitea APIs, and incomplete reverse
  configuration explicit and non-activatable by default.

**Non-Goals:**

- Organizational credentials or organization-owned API identities.
- Automatic rotation in the initial implementation.
- Recovering a token, OAuth secret, or private key after its output is lost.
- Copying secret values into Nix source, the Nix store, capture artifacts, or
  logs.
- Treating repository contents, OAuth authorization consent, or an external
  secret manager as implicitly managed.

## Decisions

### Use typed credential declarations

Add a typed attribute set below `services.osmium.gitea`, keyed by stable local
names. Each variant contains only fields valid for its kind: user token,
repository deploy key, OAuth application, or OAuth token. Use user login and
repository owner/name as Gitea identity, never API IDs alone. Reject duplicate
resource identities and unsafe output paths during evaluation.

This is preferred over one untyped option set because token scopes, SSH access
mode, and OAuth fields have different validation and lifecycle rules. API IDs
remain persisted as provenance and lookup aids, not portable declaration keys.

### Use a runtime reconciler and non-secret identity ledger

Run one ordered oneshot after Gitea and administrator bootstrap are available.
The reconciler reads the provisioning credential from its runtime file, calls
the supported Gitea API, and writes a ledger under the persistent Gitea state
directory. Ledger records contain declaration key, normalized kind/resource,
Gitea credential ID or public-key fingerprint, requested non-secret metadata,
output path metadata, and schema version. They never contain secret values or
reversible hashes of them.

For newly created credentials, the reconciler captures the one-time response
and writes output files atomically before recording successful state. If output
writing fails, it must not record success; recovery must identify whether the
remote credential already exists and require an explicit operator action rather
than silently creating another one.

### Separate deploy-key generation from Gitea registration

Gitea registers a deploy key from public SSH material; it does not serve as the
source of the private key. The provisioner will generate an SSH keypair at
runtime, submit the public key with the declared repository and read/write mode,
and write the private key to the protected output. The ledger stores the public
fingerprint and Gitea key ID. Reconciliation never regenerates a keypair for an
identified declaration.

### Treat OAuth application and token flows explicitly

OAuth application registration and OAuth token issuance will use separate typed
paths. Application creation stores client ID and secret according to the output
contract. Token creation is supported only for an explicitly implemented,
non-interactive Gitea authorization flow with declared user and scopes. The
authorization-code flow exposed by Gitea 1.27 requires interactive user
consent, so it is an explicit unsupported capability: reconciliation reports
the unsupported flow and performs no application or token mutation. Future
non-interactive capabilities must be detected before mutation and record the
API/version facts used.

### Define output files as a security boundary

Output declarations specify path, owner, group, mode, and whether the containing
state is persistent. Paths will be restricted to an approved runtime or
persistent area and written with a temporary file, restrictive umask, chmod,
and atomic rename. Secret values will be passed between subprocesses through
stdin or protected temporary files, not command-line arguments. Public metadata
may have a separate output from private material.

The module will not attempt to integrate a particular secret manager in the
first version. Operators can point output files at paths populated or persisted
by the existing deployment model, subject to the module's safety checks.

### Revoke by ledger identity, not declaration absence alone

On activation, compare the previous ledger with the current declarations. A
removed entry is revoked only when its ledger identity matches the corresponding
Gitea resource and credential kind. Revocation uses the appropriate API for
PATs, deploy keys, OAuth applications, and OAuth tokens. Failed revocation keeps
retryable non-secret state and fails visibly. No broad name-based cleanup is
performed.

### Extend one normalized observation model

Drift and live capture will normalize credential records to a common schema:
kind, stable owner/resource, supported metadata, Gitea ID/fingerprint, managed
status, provenance, unsupported fields, and secret-presence markers. Secret
fields are filtered before normalization. Candidate rendering produces output
file placeholders or explicit unresolved requirements and marks completeness
false when a secret cannot be supplied. Both paths remain stdout or
operator-selected-file operations and do not adopt or activate state.

### Use three dedicated MicroVM checks

The primary credential check will boot Gitea, provision every supported class
that the installed version exposes, verify permissions and output protections,
restart, and remove a declaration to test revocation. A drift check will mutate
credential metadata through the running API, normalize that runtime response,
convert the exact result, and consume the candidate in a separate evaluation or
reconciliation path. A live-capture check will externally create credentials,
capture the running service, convert the generated artifact, and verify the
candidate. None may use an independently authored observation fixture as the
conversion input.

## Risks / Trade-offs

- [Risk] Gitea versions expose different token or OAuth APIs → capability-detect
  supported operations, pin test expectations to the installed version, and
  report unsupported flows without fallback mutation.
- [Risk] A successful remote creation can be followed by local output failure →
  persist only non-secret pending identity, fail closed, and provide an explicit
  recovery/revoke path rather than duplicate creation.
- [Risk] Output files may be readable by unintended services → validate paths,
  ownership, mode, persistence, and atomic writes; test permissions in the
  MicroVM.
- [Risk] Revocation of a reused or externally changed credential could affect
  unrelated access → require ledger identity and compatible resource metadata,
  otherwise report a conflict and leave it untouched.
- [Risk] OAuth token issuance may require user consent or browser interaction →
  support only a documented non-interactive flow and classify Gitea 1.27's
  authorization-code flow as unsupported rather than embedding credentials or
  automation shortcuts.
- [Risk] Reverse configuration can imply that a credential is reproducible →
  emit no secret, require an operator output path, and mark candidates
  incomplete until reviewed.

## Migration Plan

1. Add typed options and evaluation assertions with no credentials declared by
   default.
2. Add the runtime ledger, reconciler, output-file handling, and capability
   checks; deploy declarations only after reviewing the generated files and
   permissions.
3. Add drift/live capture metadata and review-only candidate conversion; existing
   credentials remain unmanaged until explicitly declared and safely matched.
4. To roll back, remove declarations and allow the explicit revocation pass to
   revoke only ledger-owned credentials, then disable the feature. Unrelated
   Gitea credentials and repositories remain intact.
