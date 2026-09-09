## Purpose

Provides a safe, remote, read-only path for turning an existing Gitea
installation into a deterministic and reviewable Mythoclast declaration
candidate without treating live state or captured secrets as trusted input.

## ADDED Requirements

### Requirement: A remote Gitea installation can be captured read-only

The system SHALL connect to a configured remote host using operator-supplied
SSH transport settings and SHALL collect the supported Gitea service
configuration, runtime identity state, and persistence-relevant paths without
writing to the remote filesystem, restarting services, changing Gitea records,
or activating NixOS configuration. The initial adapter SHALL support standard
NixOS hosts and SHALL identify unsupported host layouts rather than guessing.

#### Scenario: Capture a standard NixOS Gitea host

- **WHEN** an operator provides a reachable NixOS host and a supported Gitea service
- **THEN** the system captures the service's supported configuration and live identities through read-only remote probes

#### Scenario: Remote host is unreachable

- **WHEN** SSH connection, authentication, or a required read-only probe fails
- **THEN** capture exits with an operational error identifying the failed phase and emits no complete artifact

#### Scenario: Remote host is not a supported layout

- **WHEN** the remote host does not expose the expected NixOS service configuration or Gitea state layout
- **THEN** capture reports an unsupported-host result without inferring paths or claiming completeness

#### Scenario: Capture is repeated

- **WHEN** capture runs twice against unchanged remote state with the same normalized inputs
- **THEN** the resulting artifacts are byte-for-byte identical apart from explicitly excluded transport timestamps

### Requirement: Capture artifacts are versioned, deterministic, and provenance-aware

The system SHALL emit a versioned machine-readable capture artifact containing
the adapter identity and version, remote host identity, capture scope, source
configuration and identity records, persistence paths, probe results, and
omissions. It SHALL normalize records and sort collections by stable identity,
not remote API or filesystem enumeration order. The artifact SHALL distinguish
observed values, inferred values, and operator-supplied values.

#### Scenario: Artifact records its source

- **WHEN** a remote capture succeeds or is intentionally incomplete
- **THEN** the artifact identifies the adapter, host, capture scope, and probe status needed to assess provenance

#### Scenario: Remote API order changes

- **WHEN** the same users, organizations, and settings are returned in a different order
- **THEN** normalized capture output remains byte-for-byte identical

#### Scenario: Partial capture occurs

- **WHEN** an optional probe fails while required probes succeed
- **THEN** the artifact records the failed probe and remains explicitly incomplete rather than silently dropping the result

### Requirement: The NixOS adapter discovers configuration without evaluating remote code

The initial NixOS adapter SHALL discover the Gitea service user, state directory,
configuration file locations, enabled features, endpoint, and persistence
declarations using bounded, allowlisted read-only commands and file reads. It
MUST NOT execute arbitrary shell content from the remote host, import remote
Nix expressions into the local evaluation, or treat the remote NixOS
configuration as trusted local code. Adapter output SHALL include the exact
probe names and normalized values used for conversion.

#### Scenario: Standard NixOS options are discoverable

- **WHEN** a remote service uses standard NixOS Gitea options and paths
- **THEN** the adapter captures the supported option values and maps them to the capture schema

#### Scenario: Custom service paths are declared

- **WHEN** a remote host uses supported explicit path or service overrides
- **THEN** the adapter records those paths with their source and converts them only when the target Mythoclast module can represent them

#### Scenario: Remote probe contains unsafe content

- **WHEN** a probe output contains command substitution, malformed structure, or an unallowlisted path
- **THEN** the adapter rejects or quarantines that value and records a validation finding rather than executing or normalizing it as trusted configuration

### Requirement: Captured identities and service state convert to Mythoclast declarations

The system SHALL convert a reviewed capture artifact into a deterministic
Mythoclast Gitea declaration candidate using only fields supported by the target
module. Conversion SHALL include supported non-administrator users,
organizations and ownership, service settings, persistence paths, and explicit
references for required runtime secret files when those references are
operator-supplied or safely discoverable. It SHALL produce a completeness
result and a machine-readable list of state that cannot yet be represented.

#### Scenario: Existing users and organizations are converted

- **WHEN** a complete capture contains safe non-administrator users and organizations with unambiguous owners
- **THEN** the candidate contains stable Mythoclast declarations with preserved supported metadata and owner references

#### Scenario: Existing service settings are converted

- **WHEN** captured Gitea settings have corresponding Mythoclast module options
- **THEN** the candidate contains those options without embedding runtime-generated state or secrets

#### Scenario: A required secret path is unavailable

- **WHEN** a captured user or service requires a secret but no safe target secret-file reference is supplied
- **THEN** conversion emits an explicit unresolved secret-file requirement and marks the result incomplete or non-activatable

#### Scenario: Unsupported live state exists

- **WHEN** the source contains repositories, hooks, external identity records, administrator-specific state, unsupported settings, or other data outside the target module
- **THEN** conversion lists each item with a stable reason and does not claim a fully declarative result

### Requirement: Sensitive data is never captured into declarative artifacts

The system SHALL exclude passwords, password hashes, access tokens, API keys,
SSH private keys, session credentials, secret-file contents, database
credentials, and equivalent sensitive material from capture artifacts,
conversion output, diagnostics, and error messages. It SHALL accept remote
access credentials and optional Gitea API credentials only through external
operator-managed inputs and SHALL never persist their values in generated
artifacts.

#### Scenario: Remote configuration contains credentials

- **WHEN** a configuration file or API response contains a credential-bearing field
- **THEN** the field is omitted or represented only by a non-secret presence/fingerprint marker

#### Scenario: Secret content is encountered in a file probe

- **WHEN** a read-only probe would return secret contents
- **THEN** the probe extracts only an allowlisted reference or metadata and the secret bytes do not enter output or logs

#### Scenario: Diagnostic includes a failed secret probe

- **WHEN** a credential-related probe fails
- **THEN** diagnostics identify the probe class without printing its command arguments, values, or contents

### Requirement: Capture and conversion are review-only operations

Capture and conversion SHALL write only to stdout or explicitly selected local
operator-owned artifact paths. They SHALL NOT modify the remote Gitea service,
remote NixOS files, remote persistence state, local Nix source, Mythoclast
configuration, version-control state, or running configuration. Activation
requires a separate operator-reviewed deployment workflow.

#### Scenario: Capture is exported for review

- **WHEN** an operator saves a remote capture artifact
- **THEN** remote service state and local repository state remain unchanged

#### Scenario: Candidate is edited before activation

- **WHEN** an operator fills secret paths or adjusts the generated declaration
- **THEN** no remote or local service changes occur until a separate evaluation and activation operation is requested

#### Scenario: Capture is run without an activation target

- **WHEN** an operator runs capture or conversion without selecting a deployment target
- **THEN** the workflow produces artifacts only and performs no activation

### Requirement: Future Linux adapters preserve the capture contract

The system SHALL define an adapter contract separating remote transport,
platform discovery, Gitea observation, normalization, and Mythoclast conversion.
Future adapters for other Linux distributions MAY provide equivalent read-only
probes, but SHALL emit the same capture schema and SHALL declare their support
level, probe set, and unsupported fields. A new adapter SHALL NOT weaken the
secret exclusion, provenance, completeness, or non-mutation guarantees.

#### Scenario: Adapter selection is explicit

- **WHEN** an operator selects an automatic or named adapter
- **THEN** the capture records the selected adapter and refuses ambiguous platform detection

#### Scenario: Future adapter omits a platform feature

- **WHEN** a non-NixOS adapter cannot discover a target field
- **THEN** it records the omission and conversion applies the same completeness rules as the NixOS adapter

### Requirement: Remote capture and conversion are tested end to end

The integration test SHALL boot or provision a remote NixOS test node running
Gitea, capture it through the remote transport, convert the resulting artifact,
and verify deterministic output, secret omission, unsupported-state reporting,
and non-mutation. It SHALL use the generated candidate as the input to a
separate Mythoclast evaluation or MicroVM test rather than an independently
authored equivalent fixture.

#### Scenario: Remote Gitea becomes a declarative candidate

- **WHEN** the remote test node contains safe externally created identities and supported settings
- **THEN** capture and conversion produce a deterministic Mythoclast candidate containing those values

#### Scenario: Capture does not alter the remote node

- **WHEN** the end-to-end capture and conversion workflow completes
- **THEN** remote Gitea records, configuration files, service state, and persistence contents are unchanged

#### Scenario: Generated output contains no credentials

- **WHEN** the test node contains runtime credentials and credential-bearing configuration
- **THEN** capture, conversion, and diagnostics contain no credential values or secret contents

#### Scenario: Incomplete conversion cannot be mistaken for full declaration

- **WHEN** the remote node contains unsupported or ambiguous state
- **THEN** the generated artifact identifies the omissions and fails the default completeness/activation check
