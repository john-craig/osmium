## Purpose

Provides a semi-reproducible, runtime-safe way to provision and deliver Gitea
personal tokens, SSH deploy keys, and OAuth credentials from declarative intent.

## ADDED Requirements

### Requirement: Supported Gitea credentials are declaratively configurable

The system SHALL accept a collection of credential declarations keyed by stable
local names. Each declaration SHALL identify exactly one supported credential
kind, its Gitea owner or resource, requested scopes or permissions where
applicable, and an output file for the resulting secret material. The initial
credential kinds SHALL be user personal access tokens, user SSH deploy keys,
OAuth applications, and capability-gated OAuth tokens. Organizational credentials are
outside the initial scope. An OAuth token declaration MUST fail closed when the
installed Gitea version exposes only an interactive authorization-code flow.

#### Scenario: Personal token is declared

- **WHEN** a valid personal-token declaration references an available user and
  supported scopes
- **THEN** reconciliation provisions one token for that user and writes the
  resulting token value to its declared output file

#### Scenario: Deploy key is declared

- **WHEN** a valid deploy-key declaration references a supported repository and
  declares its access mode
- **THEN** reconciliation registers one SSH public key with that repository and
  writes the corresponding private key to its declared output file

#### Scenario: OAuth application is declared

- **WHEN** a valid OAuth application declaration contains its callback and
  supported application metadata
- **THEN** reconciliation provisions one application and writes its generated
  client secret, together with non-secret client metadata, to the declared
  output locations

#### Scenario: OAuth token flow is unsupported by the installed Gitea version

- **WHEN** an OAuth token declaration requests authorization-code issuance and
  the installed Gitea API requires interactive user consent
- **THEN** reconciliation reports an unsupported-flow error and creates neither
  an OAuth application nor an OAuth token

#### Scenario: Unsupported or ambiguous declaration is present

- **WHEN** a declaration has an unknown kind, unsupported scope or flow,
  ambiguous owner/resource, unsafe output path, or missing required field
- **THEN** evaluation fails with an actionable assertion before any credential
  mutation is attempted

### Requirement: Provisioning is runtime-generated, idempotent, and identifiable

The system SHALL create credential values only after Gitea is available and
SHALL read administrator or other provisioning credentials only at runtime.
Each managed credential SHALL have a stable non-secret identity based on its
declaration key and Gitea resource identity. Reconciliation SHALL reuse an
identified existing credential and SHALL NOT create duplicates on restart.
Gitea-generated values SHALL be treated as unrecoverable after they are lost.

#### Scenario: Guest restarts with the same declaration

- **WHEN** the guest restarts with unchanged credential declarations and managed
  state and output files remain available
- **THEN** reconciliation leaves the Gitea credential unchanged and the output
  value remains usable

#### Scenario: Output value is missing

- **WHEN** managed metadata identifies an existing credential but its declared
  output file is missing or unreadable
- **THEN** reconciliation fails closed without creating a replacement or
  overwriting an unrelated credential, and reports that explicit recovery is
  required

#### Scenario: Declaration identity conflicts with existing state

- **WHEN** a declaration key or resource identity maps to multiple or
  incompatible Gitea credentials
- **THEN** reconciliation reports the conflict and performs no mutation for that
  declaration

### Requirement: Generated values are delivered through protected files

The system SHALL create or update declared output files atomically with
explicit owner, group, mode, and persistence configuration. Secret contents
SHALL be readable only by the configured recipients. Output paths SHALL be
validated against allowed locations and SHALL NOT be embedded with secret
contents in evaluated configuration, Nix store paths, persistent metadata,
process listings, logs, or diagnostics. Public deploy-key material and OAuth
client identifiers MAY be stored separately from private values.

#### Scenario: Secret output is written

- **WHEN** Gitea returns a newly generated token or OAuth secret, or the
  provisioner generates a deploy-key private key
- **THEN** the value is written atomically to the declared protected file and
  is not printed or persisted in provisioning metadata

#### Scenario: Output path is unsafe

- **WHEN** an output path is outside the configured safe area, aliases an
  unexpected existing file, or lacks valid ownership/mode configuration
- **THEN** evaluation or reconciliation refuses the declaration before secret
  material is generated or written

#### Scenario: Secret output survives impermanent restart

- **WHEN** a declared output is configured for persistence and the guest
  restarts
- **THEN** the same output value and its corresponding Gitea credential remain
  available without reprovisioning

### Requirement: Credential removal revokes only managed credentials

The system SHALL revoke a managed Gitea credential and remove or invalidate its
managed output file when its declaration is explicitly removed. It SHALL NOT
revoke credentials that cannot be proven to belong to the removed declaration.
Failure to revoke SHALL be reported and SHALL NOT be represented as successful
cleanup. Automatic rotation is not part of the initial version.

#### Scenario: Managed declaration is removed

- **WHEN** a previously reconciled credential declaration is absent from the
  next activated configuration
- **THEN** the corresponding token, deploy key, OAuth application/token, or
  other managed credential is revoked and its managed output is removed

#### Scenario: Unmanaged credential resembles a declaration

- **WHEN** a credential has no matching persisted managed identity
- **THEN** it is left untouched and no output file is removed for it

#### Scenario: Revocation fails

- **WHEN** Gitea rejects or cannot complete revocation
- **THEN** the service reports failure, retains enough non-secret state to retry,
  and does not claim the credential was revoked

### Requirement: Credential scopes and access behavior are enforced

The system SHALL pass declared token scopes, deploy-key read/write mode, OAuth
application metadata, and supported OAuth authorization scopes through the
runtime provisioning API. It SHALL reject values that Gitea cannot represent
and SHALL verify that the resulting credential metadata matches the declaration
where the API exposes it. It SHALL not grant administrator or organizational
privileges implicitly.

#### Scenario: Personal token scope is limited

- **WHEN** a token is declared with a supported restricted scope
- **THEN** the resulting token has that scope and can perform the permitted API
  operation but is rejected for an operation outside that scope

#### Scenario: Deploy key write mode is declared

- **WHEN** a repository deploy key is declared read-only or read-write
- **THEN** Git access through the resulting key has the declared access mode

#### Scenario: OAuth flow is unavailable

- **WHEN** the installed Gitea version cannot perform the declared OAuth token
  flow
- **THEN** reconciliation reports an unsupported-flow error and does not create
  an application or token as a fallback

### Requirement: Drift and live capture are review-only and secret-safe

The system SHALL detect changes to declared credential kind, owner/resource,
scopes, access mode, OAuth metadata, managed identity, and output metadata where
observable. Drift conversion and live-system capture SHALL produce deterministic,
reviewable declaration candidates with provenance and completeness status.
Neither workflow SHALL emit token values, private keys, client secrets, hashes,
or secret-file contents. A credential whose secret cannot be recovered SHALL be
represented by an explicit output-file requirement or unresolved finding, and
the candidate SHALL NOT claim complete activation readiness without operator
review.

#### Scenario: Credential metadata drifts

- **WHEN** an observed managed token scope, deploy-key mode, OAuth metadata, or
  resource association differs from its declaration
- **THEN** drift reports the changed fields and converts the observed non-secret
  metadata into a deterministic candidate without mutating Gitea

#### Scenario: Live capture observes an external credential

- **WHEN** live capture finds a supported credential not managed by the local
  declarations
- **THEN** it emits safe metadata and provenance, requires an operator-selected
  output path, and does not invent or emit the missing secret

#### Scenario: Sensitive credential data is observed

- **WHEN** an API response, database record, or local file contains a token,
  private key, client secret, or equivalent sensitive value
- **THEN** capture, drift output, conversion output, and diagnostics omit the
  value and report only a redacted presence or unresolved-state finding

#### Scenario: Reverse configuration is repeated

- **WHEN** unchanged credential metadata is captured or converted more than
  once
- **THEN** normalized output is byte-for-byte deterministic apart from explicitly
  documented observation timestamps

### Requirement: Credential provisioning is tested in MicroVMs

The implementation SHALL include MicroVM integration tests that boot and
exercise the running Gitea service. Tests SHALL verify runtime creation,
credential access behavior, protected output delivery, restart reuse, explicit
revocation, and secret omission. Separate drift-conversion and live-capture
tests SHALL generate their input from runtime observations rather than
independently authored equivalent fixtures, and SHALL verify the resulting
candidate behavior.

#### Scenario: Credentials are provisioned end to end

- **WHEN** a MicroVM boots with declared user tokens, deploy keys, and OAuth
  credentials
- **THEN** each supported credential is usable with its declared permissions,
  output files have the declared protection, and no secret appears in logs or
  evaluated artifacts

#### Scenario: Provisioned credentials are reused

- **WHEN** the credential MicroVM restarts with unchanged declarations
- **THEN** credential identifiers and output values remain unchanged and no
  duplicate credentials are created

#### Scenario: Removed credentials are revoked

- **WHEN** a declaration is removed and reconciliation runs in the MicroVM
- **THEN** the managed credential no longer authenticates or grants access, its
  output is removed, and unrelated credentials remain usable

#### Scenario: Reverse configuration uses runtime state

- **WHEN** the MicroVM externally creates or mutates supported credential
  metadata and drift or live capture is run
- **THEN** the generated candidate reflects the runtime observation, omits
  secret values, reports incomplete secret requirements, and remains review-only
