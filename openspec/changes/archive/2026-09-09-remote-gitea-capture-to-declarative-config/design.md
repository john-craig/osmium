## Context

The repository already has a Gitea NixOS module and a review-only exporter for
observed users and organizations. The new workflow must acquire input from a
different machine without turning that machine's configuration or secrets into
local trusted code. See `proposal.md` and the `remote-gitea-capture` spec for
the externally visible contract.

The initial target is standard NixOS over SSH. Gitea may be configured with
different service paths and API settings, and remote access may be available
through either a restricted SSH account or an operator-selected account with
privilege escalation. The capture process must remain read-only in either case.

## Goals / Non-Goals

**Goals:**

- Provide a deterministic capture artifact that can be reviewed independently
  of the remote host.
- Separate transport, NixOS discovery, Gitea observation, normalization, and
  candidate rendering so other distributions can add adapters later.
- Reuse the existing secret-free Gitea candidate model where possible while
  making unsupported state and missing secrets explicit.
- Make incomplete output mechanically distinguishable from activation-ready
  output and safe to inspect in CI.
- Verify the entire capture-to-candidate path against a real remote test node.

**Non-Goals:**

- Automatically adopting records, activating NixOS, changing Gitea, or writing
  remote configuration.
- Capturing or migrating repository contents, Git history, LFS objects, or
  database files as part of this change.
- Inventing secret paths or copying secret values between machines.
- Supporting arbitrary remote commands, arbitrary shell pipelines, or every
  Gitea setting in the first adapter.
- Making non-NixOS support part of the initial implementation; only the adapter
  interface is established now.

## Decisions

### Use a structured remote probe protocol

The local client will invoke a small, allowlisted probe entrypoint over SSH and
exchange framed JSON records. Each probe has a name, requested scope, result,
and sensitivity policy. Probe arguments are encoded as data rather than shell
fragments, and the client rejects unexpected fields, oversized output, invalid
UTF-8 where text is required, and absolute paths outside an allowlist.

This is preferred over scraping terminal output because it makes failures,
provenance, and normalization testable. It is preferred over copying and
evaluating the remote Nix configuration because remote expressions are not
trusted local input.

### Make adapter selection explicit and capability-based

An adapter registry will expose a stable name, version, supported probes, and
conversion capabilities. Automatic selection may use bounded platform facts,
but ties or missing facts fail closed. The NixOS adapter will read evaluated
service facts and allowlisted files, while future adapters can use distribution
specific service discovery without changing the artifact schema.

The artifact records both the adapter and each probe result. This avoids
interpreting a partial adapter result as a complete capture.

### Define one canonical capture artifact before rendering Nix

Capture output will use a versioned JSON schema with canonical serialization.
It will contain source/provenance metadata, normalized service configuration,
users, organizations, persistence facts, secret references, probe results, and
an omissions/findings list. Values will carry an origin such as `observed`,
`inferred`, or `operator-supplied`.

The renderer will consume only this artifact, not live SSH output. This makes
review, fixture testing, reproducibility, and future alternate renderers
possible.

### Treat completeness as a first-class safety property

The artifact will distinguish a complete capture from a partial capture, and a
candidate will distinguish representable state from unresolved state. The
default renderer will still produce useful candidates for review, but its exit
status and metadata will prevent an incomplete result from being treated as
activation-ready. Unsupported repositories and credentials are findings, not
silently ignored data.

### Use allowlisted secret references, never secret contents

The NixOS adapter may report that a known option points at a secret file and may
carry an operator-supplied target reference through conversion. It will never
read secret bytes. The capture schema will use explicit secret-reference
objects with a source kind and redacted presence metadata, and the generated
Nix candidate will require a reviewed target reference when one is absent.

### Keep remote access outside generated configuration

SSH host, user, identity-file, port, known-hosts policy, privilege mechanism,
and optional API token inputs are CLI or environment configuration. They are
not emitted in the candidate and are not persisted in the capture artifact
beyond non-secret provenance such as a host label or fingerprint.

## Risks / Trade-offs

- [Risk] A remote command or file may contain hostile data → use fixed probe
  commands, structured parsing, size limits, path validation, and never execute
  captured values as Nix or shell code.
- [Risk] Remote state can change during a multi-probe capture → record probe
  timestamps and a capture generation, offer a consistency check where Gitea
  supports it, and mark captures as potentially inconsistent when required
  observations span an unsafe interval.
- [Risk] Gitea versions expose different fields → version the adapter and field
  capabilities, preserve unknown fields only as redacted metadata/findings, and
  fail completeness rather than guessing.
- [Risk] SSH privilege escalation can expand read access → support a restricted
  read-only probe account first, require explicit operator configuration for
  escalation, and document the exact probe set.
- [Risk] A generated candidate may look complete while repositories or secrets
  remain outside the Mythoclast module → include a prominent completeness flag,
  machine-readable omissions, and a non-zero incomplete status.
- [Risk] Remote API credentials may leak through process arguments → accept
  them through protected file descriptors or environment handling and redact
  command diagnostics; never place them in artifact JSON.

## Migration Plan

1. Add the capture artifact schema and local fixture/validation tooling without
   changing existing Gitea activation behavior.
2. Add the NixOS SSH adapter and capture CLI; operators can run it in review-only
   mode against an existing host and inspect findings.
3. Add conversion into the existing Mythoclast Gitea declaration shape, requiring
   manual completion of unresolved secret references and unsupported state.
4. Validate and evaluate the reviewed candidate as a normal Mythoclast change;
   activation remains outside capture and conversion.
5. Roll back by removing the generated candidate and disabling the new CLI. No
   rollback action is needed on the remote host because the workflow is
   non-mutating.

## Open Questions

- Which exact Gitea settings should be considered supported by the first
  converter beyond the currently implemented identity and persistence fields?
  The adapter can report additional settings as unsupported until explicitly
  mapped.
- Should the first implementation use a remote helper installed by NixOS or a
  self-contained command uploaded/executed from the client? This does not alter
  the probe protocol or safety contract.
