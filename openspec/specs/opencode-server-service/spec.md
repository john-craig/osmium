# opencode-server-service Specification

## Purpose
Provide a reproducible OpenCode server that runs as a Home Manager-managed user
service inside an Osmium MicroVM with persistent state and runtime-only access to
host-mounted credentials and workspaces.

## Requirements

### Requirement: The OpenCode server is declaratively configurable

The service SHALL expose a disabled-by-default declaration for the OpenCode
package, dedicated user identity, Home Manager state version, server bind
address, guest and host ports, HTTP username, allowed browser origins, working
directory, OpenCode settings, credential mount, provider authentication input,
workspace mounts, persistence, and reverse-configuration tooling. Invalid,
ambiguous, colliding, unsafe, or unsupported declarations MUST fail evaluation
with actionable diagnostics.

#### Scenario: A valid server declaration evaluates

- **WHEN** an operator enables the service with valid network, credential,
  persistence, Home Manager, and workspace declarations
- **THEN** evaluation defines one identifiable OpenCode server and its required
  MicroVM integration

#### Scenario: An unsafe declaration is rejected

- **WHEN** a declaration uses a non-local listener without server
  authentication, overlapping mount points, a credential mount writable by the
  guest, an invalid path, or a colliding host port
- **THEN** evaluation fails without silently weakening or rewriting the
  declaration

### Requirement: OpenCode runs as the dedicated user's Home Manager service

The service SHALL create a locked `opencode` user with a private home directory
and a lingering user manager. Home Manager SHALL install and configure OpenCode
for that user and SHALL define the server as a systemd user service. The server
MUST start at boot without an interactive login or graphical session and MUST
run with the declared user identity, home, XDG paths, configuration, and working
directory.

#### Scenario: The MicroVM boots without a user login

- **WHEN** the enabled MicroVM reaches its normal boot target
- **THEN** the `opencode` user manager and Home Manager-defined OpenCode server
  are active without an interactive or graphical session

#### Scenario: OpenCode configuration is user-owned

- **WHEN** the running service loads its generated configuration
- **THEN** the configuration and mutable state belong to the `opencode` user and
  no system service runs the OpenCode server as root

### Requirement: Network exposure is authenticated and explicit

The server SHALL expose its declared guest port and, in a MicroVM, its declared
host-forwarded port. A non-loopback listener MUST require a non-empty runtime
server password and SHALL use the declared username for HTTP Basic Auth.
Unauthenticated or stale credentials MUST NOT reach authenticated server APIs.
Allowed browser origins MUST be limited to the declared set.

#### Scenario: An authenticated client reaches the server

- **WHEN** a client sends the declared username and current password to the
  forwarded `/global/health` endpoint
- **THEN** the server returns a successful health response identifying its
  running version

#### Scenario: An unauthenticated client probes the server

- **WHEN** a client omits credentials or supplies a previous password
- **THEN** the server rejects the request without disclosing protected server
  state

### Requirement: Host credentials are mounted read-only and consumed at runtime

The service SHALL support a dedicated host directory mounted read-only at a
declared guest credential path. Server authentication and provider
authentication MUST be read from declared files below that mount only at
runtime. Required files that are absent, empty, unreadable, malformed, or escape
the credential mount MUST prevent the server from becoming ready. Secret values
MUST NOT enter the Nix store, generated Home Manager configuration, unit command
line, process arguments, journal, diagnostics, health response, or
reverse-configuration output.

#### Scenario: Mounted credentials are valid

- **WHEN** the MicroVM starts with readable server and provider credential files
  in the declared host directory
- **THEN** the guest consumes them at runtime and starts an operational,
  authenticated OpenCode server

#### Scenario: Mounted credentials are unavailable

- **WHEN** a required credential file is missing, empty, unreadable, malformed,
  or outside the declared credential mount
- **THEN** credential reconciliation and the server fail closed without exposing
  a usable unauthenticated endpoint

#### Scenario: The guest attempts to change host credentials

- **WHEN** a guest process tries to modify a file in the credential mount
- **THEN** the write fails and the host credential bytes remain unchanged

### Requirement: Provider authentication has one-time bootstrap and rotation

The service SHALL bootstrap a valid mounted provider authentication document
atomically into the `opencode` user's persistent authentication state when no
completed state exists. It SHALL persist a secret-free completion record based
on the source content digest and MUST NOT repeat creation while that digest is
unchanged. When the mounted provider authentication file changes, the service
SHALL atomically replace the persisted authentication, update the completion
record, and restart the OpenCode user service. Failed validation or installation
MUST retain the last valid persisted authentication and MUST NOT mark the new
digest complete.

#### Scenario: Provider authentication is bootstrapped once

- **WHEN** the service first starts with a valid provider authentication file
- **THEN** it installs the authentication with private ownership and mode,
  records completion without secret bytes, and does not reinstall it on an
  unchanged restart

#### Scenario: Provider authentication changes

- **WHEN** the mounted provider authentication file receives different valid
  content
- **THEN** the service installs the replacement atomically, restarts OpenCode,
  and subsequent provider operation uses the replacement rather than the old
  credential

#### Scenario: Replacement authentication is invalid

- **WHEN** changed provider authentication is malformed or cannot be installed
- **THEN** rotation reports failure, preserves the last valid authentication,
  and does not record the invalid content as applied

### Requirement: Server authentication rotates with changed secret content

The service SHALL detect a changed value in its mounted server environment file
and restart the OpenCode user service so the replacement password is consumed at
runtime. The rotation state SHALL contain only a digest and operational metadata.
After successful rotation, the old password MUST fail and the replacement MUST
succeed. An invalid replacement MUST fail closed rather than leave an
unintentionally unauthenticated listener.

#### Scenario: Server password changes

- **WHEN** the host replaces the mounted server environment file with a valid
  file containing a different password
- **THEN** OpenCode restarts, rejects the previous password, and accepts the
  replacement password

#### Scenario: Server password replacement is invalid

- **WHEN** the replacement file lacks a valid non-empty server password
- **THEN** readiness fails and no unauthenticated server is exposed

### Requirement: Persistent state and mounted workspaces have separate lifecycles

The service SHALL persist the OpenCode user's supported session, data, provider
authentication, and credential-reconciliation state across an impermanent guest
reboot. Credential mounts MUST remain non-persistent and read-only. Workspace
mounts SHALL be declared separately with an explicit guest path and read-only or
read-write policy; read-write access MUST require explicit opt-in and compatible
host ownership. Removing a declaration MUST NOT delete host workspace data or
persisted OpenCode state.

#### Scenario: The guest reboots

- **WHEN** the MicroVM reboots after OpenCode has created session state and
  completed provider authentication bootstrap
- **THEN** the server returns to ready state with the same supported session and
  authentication state without repeating unchanged bootstrap

#### Scenario: A read-only workspace is mounted

- **WHEN** OpenCode reads a declared read-only host workspace and attempts a
  write
- **THEN** existing project content is visible and the write is denied

#### Scenario: A writable workspace is mounted

- **WHEN** an operator explicitly declares a compatible read-write workspace
  and OpenCode creates a file in it
- **THEN** the file is visible on the host with the expected ownership semantics

### Requirement: Lifecycle and readiness are deterministic

The service SHALL order credential mounts, persistence, provider bootstrap, the
lingering user manager, and the Home Manager user service so that readiness is
reported only after all required dependencies succeed. Repeated starts with
unchanged inputs MUST be idempotent. A health check SHALL distinguish a healthy,
authenticated OpenCode server from a process that is merely listening or lacks
usable provider authentication.

#### Scenario: Unchanged service restarts

- **WHEN** the service restarts repeatedly with unchanged configuration and
  credentials
- **THEN** it returns to equivalent ready state without duplicating bootstrap or
  corrupting persisted state

#### Scenario: A required dependency fails

- **WHEN** credential mounting, provider reconciliation, persistence, or the user
  service fails
- **THEN** readiness reports the failed dependency and does not claim the server
  is operational

### Requirement: OpenCode configuration uses a pinned typed generator

The server SHALL generate profile-related agents, skills, MCP servers, and
permissions through a pinned typed OpenCode configuration schema. Existing
server settings SHALL remain composable with generated profile configuration,
and conflicting declarations MUST fail evaluation rather than use an implicit
precedence rule.

#### Scenario: Existing settings compose with profiles

- **WHEN** an operator declares compatible base server settings and one or more
  profiles
- **THEN** the generated configuration contains both sets of settings and passes
  typed schema validation

#### Scenario: Existing settings conflict with generated profile state

- **WHEN** base settings redefine a generated profile agent, skill registry, MCP
  server, or permission boundary incompatibly
- **THEN** evaluation fails with an actionable conflict diagnostic

### Requirement: Server sessions expose selected profile identity

The server SHALL preserve the selected profile identity on message handling.
Profile selection MUST be explicit through the authenticated
`POST /session/:id/message` API and MUST remain stable for the session unless an
authenticated client explicitly switches to another enabled profile.

#### Scenario: A profile remains selected across turns

- **WHEN** a client selects a profile on a message and sends multiple messages
- **THEN** every turn uses the selected profile until an explicit valid switch

#### Scenario: A profile is disabled after configuration replacement

- **WHEN** a session references a profile that is no longer enabled after a
  configuration deployment
- **THEN** new sessions cannot select it and existing behavior is reported
  explicitly rather than silently mapped to another profile

### Requirement: Server reverse configuration includes profiles

The server's drift and live-capture paths SHALL include all supported profile,
rule, skill, MCP, and profile-permission attributes. Both paths MUST preserve
their existing secret-exclusion, provenance, completeness, non-mutation, and
review-only guarantees.

#### Scenario: Server drift includes a profile

- **WHEN** profile configuration differs from the declaration and server drift
  conversion runs
- **THEN** the server candidate includes the observed non-secret profile state
  and marks unobservable inputs unresolved

#### Scenario: Server capture includes profiles

- **WHEN** live capture observes a running server with selected profiles
- **THEN** the output includes deterministic profile state without credential
  values and without claiming completeness for unobservable sources

### Requirement: Supported attributes have drift reverse configuration

The service SHALL provide a non-mutating drift observation and conversion path
for every supported declarative attribute. It SHALL compare declared state with
runtime-observed user, unit, listener, mount, workspace, persistence,
configuration, authentication-state, and readiness facts and produce a
deterministic, review-only Osmium declaration candidate. Output MUST include
provenance, scope, completeness, unsupported or ambiguous state, and secret
exclusions. It MUST use unresolved placeholders for host-only paths or secret
inputs that cannot be safely observed and MUST NOT claim completeness when
required state is unavailable or unrepresentable.

#### Scenario: Runtime drift produces a candidate

- **WHEN** a supported server, user-service, mount, workspace, or OpenCode
  setting differs at runtime and drift conversion runs
- **THEN** the candidate is derived from the observed difference, identifies its
  provenance, and contains the supported non-secret replacement declaration

#### Scenario: Drift includes secret or host-only state

- **WHEN** observation encounters credential bytes or a host source path that is
  not observable safely inside the guest
- **THEN** the output omits secret bytes, uses an explicit unresolved input where
  necessary, and marks the candidate incomplete rather than inventing a value

#### Scenario: Drift conversion is review-only

- **WHEN** drift conversion produces a candidate
- **THEN** it does not change the running server, credentials, mounts, Nix source,
  Home Manager generation, persistence state, or version-control state

### Requirement: Running state supports live-capture reverse configuration

The service SHALL provide a non-mutating live-capture path that reconstructs
every supported declarative attribute from the running MicroVM's observable
facts rather than from an independently authored equivalent fixture. Capture
output SHALL be deterministic and SHALL describe provenance, capture scope,
completeness, secret exclusions, unsupported state, and ambiguity. It MUST NOT
emit credential values or claim complete host mount declarations when host-only
source paths cannot be observed.

#### Scenario: A running service is captured

- **WHEN** live capture observes the running user service, network endpoint,
  generated OpenCode configuration, mounts, persistence, and reconciliation
  records
- **THEN** it produces a reviewable Osmium declaration whose represented
  behavior evaluates and starts an equivalent server after unresolved inputs are
  supplied

#### Scenario: Capture is repeated

- **WHEN** unchanged runtime state is captured twice
- **THEN** both outputs are byte-for-byte identical apart from explicitly
  documented volatile metadata

#### Scenario: Capture cannot observe required state

- **WHEN** required runtime facts are unavailable, ambiguous, unsupported, or
  secret
- **THEN** capture records the limitation, emits no fabricated value, and marks
  the candidate incomplete

### Requirement: Dedicated MicroVM checks verify the service and conversions

The change SHALL provide separate executable flake checks that boot and exercise
the OpenCode service MicroVM, drift conversion, and live-capture conversion.
The checks MUST verify behavior through running guest services and runtime
observations rather than only evaluating options, building closures, or comparing
against independently authored equivalent declarations.

#### Scenario: The primary service check runs

- **WHEN** `nix build .#checks.x86_64-linux.opencode-server --print-build-logs`
  runs
- **THEN** it boots the MicroVM and verifies unattended Home Manager user-service
  startup, authenticated health, provider operation, read-only credential and
  workspace mounts, explicit writable workspace behavior, persistence across
  reboot, one-time bootstrap, both changed-secret rotation paths, failure modes,
  and secret non-disclosure

#### Scenario: The drift conversion check runs

- **WHEN** `nix build .#checks.x86_64-linux.opencode-server-drift-reverse-configuration --print-build-logs`
  runs
- **THEN** it boots the MicroVM, introduces supported runtime drift, derives a
  candidate from that observation, verifies safety and incompleteness metadata,
  and verifies the resulting declaration behavior after explicit unresolved
  inputs are supplied

#### Scenario: The live-capture conversion check runs

- **WHEN** `nix build .#checks.x86_64-linux.opencode-server-live-capture-reverse-configuration --print-build-logs`
  runs
- **THEN** it boots the MicroVM, captures the running service, proves the
  candidate came from runtime facts, verifies deterministic and secret-free
  output, and verifies the resulting declaration behavior after explicit
  unresolved inputs are supplied
