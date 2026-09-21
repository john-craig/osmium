## Context

Osmium service modules wrap native NixOS services in persistent MicroVM guests.
Gitea establishes the existing pattern for runtime administrator bootstrap,
declarative user reconciliation, one-time credential delivery, non-secret
ledgers, and review-only reverse configuration. Gotify supplies a native NixOS
module with environment-file support, but its user passwords and generated
application tokens require a runtime lifecycle. See `proposal.md` and the
Gotify specifications for the observable contract.

## Goals / Non-Goals

**Goals:**

- Establish a small Gotify-specific module that composes the native NixOS
  service with Osmium persistence and MicroVM networking.
- Safely reconcile users and user-owned applications through supported Gotify
  administrative APIs, retaining only non-secret identity state.
- Treat application-token delivery and reverse configuration as explicit,
  failure-safe security boundaries.

**Non-Goals:**

- Multiple Gotify instances, external database deployment, TLS/reverse-proxy
  automation, or general notification routing.
- User API/client tokens, administrator rotation, password recovery, token
  recovery after a lost output, or automatic adoption of existing resources.
- Capturing or replaying passwords, application tokens, or API credentials.

## Decisions

### Compose the native Gotify module

Add `modules/services/gotify.nix`, enabling `services.gotify` and mapping
Osmium options to its state-directory and environment configuration. Persist
the complete configured Gotify state directory and expose one configurable HTTP
guest/host mapping with evaluation assertions. This follows the native-service
approach used by Gitea rather than an OCI image, preserving reproducibility and
avoiding image lifecycle management.

### Bootstrap the administrator with a completion marker

The module will offer `admin` options analogous to Gitea: enablement, username,
and `passwordFile`. A pre-start/bootstrap oneshot will consume the file only at
runtime and use Gotify's supported initial-account configuration or
administrative API. It will record a versioned, non-secret completion marker in
the persisted state directory only after it can authenticate as that account.
Subsequent starts will verify the account and marker, never reset or rotate the
password. This is preferred to Nix-evaluated defaults because passwords stay
outside the store and because default-account configuration alone cannot prove
one-time completion.

### Model users and applications as typed declarations

Use `services.osmium.gotify.users` keyed by local declaration name with
`username`, `passwordFile`, and non-admin metadata, plus
`services.osmium.gotify.applications` keyed by declaration name with owner,
name, description, and output metadata. Evaluation asserts unique identities,
declared ownership, valid file recipients, and safe output locations. Password
rotation is detected through a salted, one-way state comparison that retains no
plaintext or reversible digest; app tokens are intentionally not rotated.

This avoids a generic untyped resource collection and makes ownership, secret
inputs, and one-time token semantics clear at evaluation time.

### Reconcile at runtime with a non-secret ledger

An ordered oneshot will run after Gotify and administrator bootstrap. It reads
administrator and user password files at runtime, uses supported Gotify APIs to
look up/create/update users and applications, and writes a versioned ledger
under the persisted state directory. Ledger records contain local declaration
key, normalized owner/application identity, remote IDs, observable metadata,
output metadata, password rotation salt/digest, and status, but never passwords
or token values.

On creation, persist pending non-secret app identity before atomically writing
the returned token. If output writing fails or an output later disappears, fail
closed instead of issuing a replacement. Removal uses compatible ledger IDs and
metadata, never broad name matching, and user deletion is refused if safe
ownership cannot be proven.

### Define app-token output files as a security boundary

Outputs must specify a permitted absolute location, owner, group, mode, and
persistence intent. The reconciler will use a restrictive umask, protected
temporary files, atomic rename, and non-command-line secret transport. Token
values are not emitted in state, Nix values, process listings, logs, capture
artifacts, or diagnostics. Persistent outputs are added to the impermanence
declaration when requested.

### Share one sanitized observation model for reverse configuration

Implement `osmium-gotify-drift`, `osmium-gotify-export`, and
`osmium-gotify-capture` around a normalized observation of user/application
metadata, managed status, provenance, unsupported fields, and redacted secret
presence. Conversion emits explicit `passwordFile` and token-output placeholders
and marks output incomplete until an operator reviews and supplies those
requirements. Both paths only read Gotify and write an operator-selected report;
they never adopt or activate resources.

### Use four MicroVM integration checks

`gotify` verifies native service startup, bootstrap, authenticated HTTP, and
persistence. `gotify-provisioning` verifies users, app-token output protection,
notification delivery, restart reuse, password-file change, and removal.
Dedicated drift and live-capture checks each create or mutate runtime state,
convert that exact observation, evaluate or reconcile the generated candidate's
safe metadata behavior, and prove no source/ledger/service mutation. This meets
the repository requirement that new services and declarative reverse paths boot
and exercise the MicroVM.

## Risks / Trade-offs

- [Gotify API availability differs from the pinned package] → Capability-check
  required endpoints before mutation, pin expectations to the flake lock, and
  fail with an actionable unsupported-capability error.
- [Remote app creation succeeds but local token delivery fails] → Persist only a
  pending non-secret identity and require explicit recovery or deletion rather
  than silently issuing another token.
- [User password drift cannot be queried from Gotify] → Compare a salted,
  one-way runtime-file digest only in local protected state; never treat it as a
  remotely observable secret or emit it during capture.
- [Deleting users can remove unmanaged state] → Require ledger proof and a safe
  ownership check, otherwise fail the removal without mutation.
- [Reverse configuration could imply secrets are reproducible] → Render
  secret-file/output placeholders, provenance, and `complete = false`; omit all
  secret values and hashes.

## Migration Plan

1. Add the service disabled by default, native Gotify wiring, persistence, and
   the bootstrap lifecycle; deploy only after administrator password-file
   permissions are reviewed.
2. Add user/application declarations and reconcile against a fresh or
   explicitly reviewed Gotify instance. Existing accounts and applications stay
   unmanaged until declared and safely matched.
3. Add drift and live-capture tooling as review-only commands; operators review
   candidates and supply secret file/output locations before activation.
4. Roll back by removing application declarations to invoke verified managed
   cleanup, then disable the service. Preserve the state directory for manual
   recovery unless deliberate destruction is requested.
