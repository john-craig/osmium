## Purpose

Provide a reproducible, self-contained F-Droid repository endpoint that can be
deployed and tested as a persistent Osmium MicroVM service.

## ADDED Requirements

### Requirement: Repository service is declaratively configurable
The service SHALL expose a disabled-by-default configuration for one F-Droid
repository, including its stable identity, display metadata, base URL, guest
HTTP port, and declared prebuilt application artifacts with their supported
metadata. Invalid, ambiguous, duplicate, or unsupported declarations MUST fail
evaluation with actionable diagnostics.

#### Scenario: Valid repository declaration evaluates
- **WHEN** an operator enables the service with valid repository metadata and a
  supported artifact declaration
- **THEN** the NixOS configuration evaluates and defines one identifiable F-Droid
  repository service

#### Scenario: Invalid declaration is rejected
- **WHEN** an artifact path, package identity, port, or metadata value violates
  the supported contract
- **THEN** evaluation fails without silently dropping or rewriting the value

### Requirement: Repository content and indexes are served over HTTP
The service SHALL serve repository metadata, signed indexes, icons, and declared
APK artifacts from a stable HTTP root. A client-compatible index probe MUST be
able to distinguish a ready repository from a service that has not generated its
indexes.

#### Scenario: F-Droid client metadata is reachable
- **WHEN** the running service has completed its initial generation
- **THEN** requests for repository metadata and the supported signed index
  artifacts return successful responses with the declared repository identity

#### Scenario: Declared APK is downloadable
- **WHEN** a client requests an artifact represented in the generated index
- **THEN** the service returns the exact artifact bytes and the index references
  its supported metadata and checksum

### Requirement: Index generation and signing are reproducible and secret-safe
The service SHALL generate indexes from the declared repository inputs and SHALL
sign generated indexes using operator-provided runtime secret-file references.
Private key and password bytes MUST NOT be embedded in evaluated configuration,
service arguments, logs, diagnostics, or reverse-configuration output. Missing
or unusable signing material MUST make the service fail closed rather than serve
an index that claims to be trusted.

#### Scenario: Signing material is consumed at runtime
- **WHEN** the service starts with readable signing secret files
- **THEN** it generates valid signed indexes without exposing secret contents in
  the system closure or journal

#### Scenario: Signing material is unavailable
- **WHEN** required signing material is absent, unreadable, or invalid
- **THEN** generation reports a readiness failure and does not publish a trusted
  repository index

### Requirement: Service state survives impermanent guest reboot
The service SHALL declare its repository state, generated indexes, configured
artifact store, and signing-related runtime state through Osmium persistence.
Restarting or rebooting the MicroVM MUST not require re-importing artifacts or
change the repository identity solely because the root filesystem was recreated.

#### Scenario: Repository survives reboot
- **WHEN** a MicroVM is rebooted after successful generation
- **THEN** the service returns to ready state and serves the same repository
  metadata, index entries, and APK bytes

### Requirement: Lifecycle is safe and non-destructive
The service SHALL reconcile declared metadata and artifacts idempotently on
startup. Removing a declaration MUST NOT delete persisted APKs or repository
history unless an explicit destructive cleanup operation is later introduced.
Conflicts between an existing artifact identity and a changed artifact checksum
MUST stop reconciliation and identify the conflict.

#### Scenario: Restart is idempotent
- **WHEN** the service starts repeatedly with unchanged declarations
- **THEN** it produces equivalent repository output without duplicating or
  corrupting artifacts

#### Scenario: Artifact conflict is rejected
- **WHEN** a declared artifact identity resolves to bytes whose checksum differs
  from the previously persisted artifact
- **THEN** reconciliation reports a conflict and does not silently replace the
  persisted artifact

### Requirement: Supported declarative attributes have drift reverse configuration
The service SHALL provide a read-only drift observation and conversion path for
all supported declarative repository attributes. The conversion MUST be
deterministic, provenance-aware, secret-free, explicit about unsupported or
ambiguous state, and MUST NOT mutate the running service, Nix source, adoption
state, or version-control state. Incomplete observations MUST NOT be marked
ready for activation.

#### Scenario: Runtime metadata drift becomes a review candidate
- **WHEN** an operator changes supported repository metadata or artifact
  attributes through an external runtime operation and runs drift conversion
- **THEN** the output records the observed changes and produces a review-only
  declaration candidate derived from that runtime observation

#### Scenario: Drift output omits sensitive state
- **WHEN** the observed repository includes signing material, private keys,
  passwords, or unsupported content state
- **THEN** the report omits secret bytes and records explicit exclusions or
  unresolved requirements instead

### Requirement: Running repository state supports live capture
The service SHALL provide a read-only live capture and conversion path that
reads supported repository metadata and artifacts from the running service,
including capture scope, provenance, capability facts, completeness, and stable
ordering. Repeated capture of unchanged state MUST be byte-for-byte equivalent.

#### Scenario: Live capture preserves repository identity
- **WHEN** capture runs against a ready repository containing declared artifacts
- **THEN** the generated declaration candidate contains the observed repository
  identity, metadata, artifact identities, and provenance rather than an
  independently authored fixture

#### Scenario: Partial capture is explicit
- **WHEN** an artifact, required metadata field, or supported capability cannot
  be observed
- **THEN** the capture is marked incomplete and the conversion identifies the
  missing state rather than claiming a complete declaration

### Requirement: MicroVM networking and integration behavior are explicit
The service SHALL expose a configurable guest HTTP port and deterministic host
forwarding in the MicroVM example or test configuration, with evaluation-time
collision checks. A dedicated integration check SHALL boot the MicroVM and
exercise readiness, metadata delivery, APK delivery, persistence across reboot,
drift conversion, and live-capture conversion from runtime-generated state.

#### Scenario: MicroVM integration check verifies end-to-end behavior
- **WHEN** `nix build .#checks.x86_64-linux.fdroid-repository --print-build-logs`
  runs
- **THEN** it boots the service MicroVM, verifies client-compatible repository
  output and an APK checksum, reboots and repeats the probe, and verifies both
  reverse-configuration candidates are generated from observations made during
  the test
