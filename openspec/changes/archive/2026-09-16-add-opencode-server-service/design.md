## Context

See `proposal.md` for motivation. Osmium services currently use NixOS modules,
impermanence, `microvm.nix`, runtime secret-file references, and booting NixOS
tests. Home Manager is only a transitive lock-file input and no current Osmium
service defines a systemd user service or a host directory share.

Panoply demonstrates an OpenCode web user service with runtime Basic Auth,
while nixpkgs-apocrypha demonstrates a dedicated OpenCode account and generated
OpenCode configuration. The current Home Manager module provides
`programs.opencode`, `programs.opencode.web`, and a runtime `environmentFile`.
The pinned `microvm.nix` supports read-only 9p or virtiofs directory shares.

Repository policy requires every new declarative attribute to participate in
both drift-based and live-capture reverse configuration, each verified by a
dedicated booting MicroVM test. Privileged credential bootstrap and changed-file
rotation must also be exercised in a MicroVM.

## Goals / Non-Goals

**Goals:**

- Keep OpenCode configuration and process ownership in the `opencode` user's
  Home Manager profile while using NixOS for identity, persistence, mounts,
  networking, and boot ordering.
- Make a newly booted MicroVM operational with host-supplied HTTP and provider
  credentials without embedding secrets in Nix artifacts. Provider operation is
  not part of the current deterministic integration coverage.
- Separate immutable configuration, persistent user state, read-only
  credentials, and independently declared project workspaces.
- Provide testable one-time provider authentication bootstrap and deterministic
  changed-secret rotation.
- Reconstruct all supported declarations safely from runtime observations.

**Non-Goals:**

- Managing host secret decryption; the host supplies a prepared directory,
  commonly from `sops-nix` or another runtime secret manager.
- Sharing OpenCode session databases between multiple guests or hosts.
- Automatically selecting, purchasing, or validating a particular commercial
  model provider account.
- Providing a public TLS reverse proxy; the service exposes an authenticated
  guest endpoint and host port for a separate proxy or local client.
- Deleting persisted OpenCode data or host workspace content when declarations
  are removed.
- Reusing Panoply's writable mixed credentials-and-logs shares.

## Decisions

### Use Home Manager's native OpenCode modules

Add Home Manager as an explicit flake input following `nixpkgs`, import its NixOS
module in Osmium's default guest module, and configure
`home-manager.users.opencode.programs.opencode` plus
`programs.opencode.web`. The NixOS wrapper owns cross-boundary concerns, but the
server unit remains a Home Manager systemd user service as requested.

This is preferred over copying Panoply's custom unit because current Home
Manager already models the OpenCode package, JSON configuration, and web service
environment file. A small user-unit override may add headless boot ordering,
credential reconciliation dependencies, restart triggers, and hardening without
forking the whole service implementation.

### Use one locked, lingering service account

Create `opencode` as a normal user with a stable configurable UID, an `opencode`
primary group, a locked password, a private home (default
`/var/lib/opencode`), and `linger = true`. The user manager starts at boot and
the Home Manager service targets `default.target`, not
`graphical-session.target`. The service never requires a login session.

A normal user is chosen because Home Manager and systemd user services have
well-defined behavior for it. Running OpenCode as root or as a system-level
unit would violate the ownership and configuration boundary.

### Expose a bounded option surface

The initial `services.osmium.opencodeServer` interface will cover:

- `enable`, `package`, `user`, `group`, `uid`, `home`, and
  `homeStateVersion`;
- `listenAddress`, `guestPort`, `hostPort`, `httpUsername`, `corsOrigins`, and
  `workingDirectory`;
- `settings`, `tui`, and `extraPackages` passed to Home Manager's OpenCode
  module;
- `credentials.hostDirectory`, `credentials.guestDirectory`,
  `credentials.serverEnvironmentFile`, and
  `credentials.providerAuthFile`;
- `workspaces.<name>.hostPath`, `guestPath`, `readOnly`, and share protocol
  controls supported by the pinned MicroVM implementation;
- `persistence.enable` and `reverseConfiguration.enable`.

Credential filenames are relative, traversal-free names below the one declared
credential mount. The module joins them to the guest directory. A host directory
is required when the MicroVM module is present; a non-MicroVM deployment may
arrange the same guest directory externally. Workspace guest paths must be
absolute, unique, non-overlapping, outside credential and persistent state
paths, and explicitly writable when mutation is intended.

Arbitrary Home Manager fragments are not exposed because they cannot be safely
or completely reverse configured. The bounded JSON settings and package lists
provide useful customization while preserving an observable contract.

### Mount credentials as a dedicated read-only MicroVM share

When MicroVM options are available, generate one `microvm.shares` entry from the
credential declaration with `readOnly = true`, a stable tag, and a protocol
supported by the selected hypervisor. Credentials and diagnostics never share a
mount. The unit requires the guest mount and validates ownership-independent
readability, non-empty content, path containment, and format before startup.

The source directory is prepared by the host and should be runtime-only with
mode `0700`; files should be `0400` or `0440`. Because host and guest identities
may not share numeric IDs, the design does not assume the guest can infer or
change host ownership. The MicroVM check will use a fixture directory outside
the Nix store for actual secret values and prove writes from the guest fail.

This is preferred over copying credentials into the guest, placing them in a
persistent volume, or using a writable shared directory. Those alternatives
either duplicate secret lifetime, leave stale values, or allow guest mutation.

### Use an environment file for server authentication

The mounted server environment file is consumed by Home Manager's
`programs.opencode.web.environmentFile`. It must contain a non-empty
`OPENCODE_SERVER_PASSWORD`; `OPENCODE_SERVER_USERNAME` is generated from the
non-secret declaration. No password value appears in Nix, the unit command line,
or generated OpenCode JSON.

The listener defaults to loopback. Host forwarding or another non-loopback
listener requires the environment file. The service health probe authenticates
at runtime without placing the password in a URL or logs.

### Reconcile provider authentication atomically

Treat the mounted provider authentication document as an opaque OpenCode auth
JSON document. A root-owned oneshot validates that it is non-empty JSON, then a
user-context installer atomically writes it to OpenCode's supported XDG data
location with mode `0600`. The precise location is derived from the pinned
OpenCode package behavior during implementation rather than duplicated in the
public interface.

The reconciler computes a cryptographic digest and stores only the digest,
timestamp-free status, and schema version in persistent state. On first start it
installs and records the document. With the same digest it performs no write. On
a changed valid digest it atomically replaces authentication and restarts the
user service. Invalid replacements leave the last valid file and completion
record untouched.

A path-triggered unit plus a periodic reconciliation timer handles mounted-file
changes; digest comparison is authoritative because file notification behavior
varies by share protocol. This fulfills one-time bootstrap and rotation without
requiring provider-specific CLI prompts.

### Rotate the HTTP credential by content digest

Track a separate digest for the server environment file. A valid changed digest
restarts the Home Manager user service so systemd reloads the file. Validation
occurs before the restart. An invalid file stops readiness and the non-loopback
service rather than allowing fallback to unauthenticated behavior. Tests verify
the old password fails and the replacement succeeds.

### Keep persistence and shares independent

Persist the complete supported OpenCode user data boundary and reconciliation
records through `environment.persistence."/persistent"`. Generated Home Manager
configuration remains immutable. Credential and workspace mounts are never
included in guest persistence. Removal of the service declaration does not
perform destructive cleanup.

Workspace shares default to read-only. Read-write is explicit and relies on a
compatible `microvm.nix` security model and host permissions. The implementation
will document the required UID/GID behavior and reject combinations unsupported
by the pinned hypervisor or protocol.

### Generate observations from runtime facts

Install a secret-free declaration ledger containing declared non-secret values
and field provenance. Drift tooling compares it with runtime facts from the
passwd database, user unit properties, process identity, listener, mount table,
Home Manager-generated JSON, persistence paths, health endpoint, and credential
digest records. It does not treat the ledger alone as proof of runtime state.

Live capture starts from those runtime facts and uses the ledger only to recover
safe declaration names or values that are inherently declarative. Host share
source paths and credential contents are not observable safely from inside the
guest. Their fields use activation-blocking placeholders and the candidate is
marked incomplete until an operator supplies them.

Both tools produce stable JSON observations and deterministic Nix-shaped review
candidates. They write only to stdout or an explicitly selected operator-owned
path and never activate, edit source, change Home Manager, restart services, or
touch credentials.

### Use three booting integration checks

`opencode-server` boots a MicroVM with host-created credential and workspace
directories, then verifies:

- boot-time lingering and the Home Manager user unit;
- authenticated and unauthenticated health behavior;
- read-only credential and workspace mounts plus an explicitly writable
  workspace;
- persistence across reboot and unchanged-bootstrap idempotence;
- valid and invalid provider-auth rotation;
- changed server-password rotation;
- absence of secret values from closure-facing files, process arguments,
  journal, health, and reverse outputs.

The primary check deliberately does not invoke the OpenCode CLI or claim a real
provider request. The pinned CLI's interaction with the NixOS test-driver stream
is currently unstable, so provider-operation coverage is deferred until it can
be isolated without corrupting test-driver protocol traffic. The check covers
provider-auth bootstrap, persistence, validation, and rotation only.

`opencode-server-drift-reverse-configuration` boots the service, changes
supported observable runtime state without editing the declaration, invokes
drift conversion, and verifies the candidate is derived from that mutation. It
then supplies explicit unresolved host/secret paths and boots/evaluates the
candidate behavior rather than comparing only text fixtures.

`opencode-server-live-capture-reverse-configuration` boots the service, captures
runtime-generated facts, verifies deterministic and secret-free output and
provenance, supplies unresolved inputs, and verifies equivalent server behavior
in a booted MicroVM.

### Pinned test-driver host-share limitation

The pinned NixOS test driver exposes `Machine.shared_dir` and
`Machine.state_dir` to Python test scripts, but virtiofs source paths are fixed
before the script runs. The integration tests therefore use the driver's
stable `shared` and `xchg` 9p exports, then explicitly bind-mount them at the
declared credential and workspace paths after boot and after reboot. This keeps
fixture creation runtime-derived without relying on a deleted helper or on
writable credential shares. Production credential shares remain read-only with
`cache = "never"`; writable access is limited to the declared writable
workspace test mount.

## Risks / Trade-offs

- [Home Manager module behavior changes across revisions] -> Pin Home Manager in
  `flake.lock`, follow the repository's nixpkgs revision, and test generated unit
  properties and runtime behavior.
- [Provider auth JSON is an internal OpenCode format] -> Pin the OpenCode package,
  validate against actual package behavior, keep the public input opaque, and
  cover bootstrap and lifecycle behavior in the MicroVM test; defer an actual
  provider operation until CLI/test-driver isolation is reliable.
- [Secrets are visible in the OpenCode process environment] -> Use systemd's
  runtime environment-file mechanism, restrict process ownership, avoid command
  line values and debug tracing, and test all public diagnostics for leakage.
- [Share change notification can be unreliable] -> Treat digest reconciliation
  as authoritative and combine path activation with a bounded periodic timer.
- [A compromised OpenCode process can read mounted provider credentials] -> Use
  a dedicated read-only mount containing only credentials required by that
  server; do not expose unrelated host secrets.
- [Writable workspaces weaken host isolation] -> Default to read-only, require
  explicit opt-in, validate mount separation, and document host ownership
  requirements.
- [Guest capture cannot recover host source paths] -> Emit unresolved,
  activation-blocking placeholders with incomplete status rather than fabricating
  a complete declaration.
- [OpenCode CLI interaction corrupts the pinned test-driver stream] -> Keep the
  primary check on deterministic HTTP and credential lifecycle behavior and
  defer provider-operation coverage rather than claiming an unverified request.

## Migration Plan

1. Add and lock the explicit Home Manager input following nixpkgs.
2. Add the service module disabled by default; existing guests are unaffected.
3. Add the primary MicroVM check and verify credentials, persistence, and
   rotation before publishing an example configuration; track provider
   operation separately until deterministic CLI coverage is available.
4. Add and execute the two reverse-configuration MicroVM checks.
5. Deploy by preparing the host credential directory, selecting non-conflicting
   ports and workspace shares, then enabling the service in one guest.
6. Roll back by activating the previous host/guest generation. Leave persistent
   state and host workspace data intact for recovery; remove them only through a
   separate explicit operator action.
