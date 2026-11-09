## Purpose

Provide a bounded OpenCode support profile that uses the same server's
`opencode-mcp` interface to inspect, create, select, and communicate with other
sessions through verified runtime behavior.

## ADDED Requirements

### Requirement: The support profile is declarative and disabled by default

The service SHALL provide a disabled-by-default support profile backed by a
pinned `opencode-mcp` package. Enabling it SHALL register one local MCP server,
one selectable primary profile, and the runtime connection settings required to
reach the same OpenCode server. The support MCP MUST NOT start a second OpenCode
server and MUST fail evaluation for conflicting generated profile or MCP names.

#### Scenario: An operator enables the support profile

- **WHEN** an operator enables the support profile with a valid model and
  non-conflicting names
- **THEN** evaluation produces a selectable support profile with the pinned
  local OpenCode MCP server in its allowlist

#### Scenario: The support profile remains disabled

- **WHEN** the support-profile declaration is omitted or disabled
- **THEN** no support profile, OpenCode MCP registration, or support runtime state
  is generated

#### Scenario: Generated names conflict

- **WHEN** an operator declaration already defines the generated profile or MCP
  server name incompatibly
- **THEN** evaluation fails with an actionable conflict rather than applying an
  implicit precedence rule

### Requirement: The support MCP connects securely to the same server

The support MCP SHALL connect to the running OpenCode server through its declared
guest endpoint and SHALL consume HTTP authentication only through runtime
environment references. It MUST use the server's current username and password,
MUST disable automatic server startup, and MUST NOT place credential values in
the Nix store, generated OpenCode configuration, process arguments, journals,
diagnostics, observations, or reverse-configuration output.

#### Scenario: Server authentication is configured

- **WHEN** the OpenCode server and support profile start with valid mounted
  credentials
- **THEN** the MCP authenticates to that same server without exposing the
  username or password as command-line arguments or generated secret literals

#### Scenario: The server password rotates

- **WHEN** the mounted server password changes and credential reconciliation
  applies the replacement
- **THEN** the support MCP reconnects with the replacement credential, rejects
  the previous credential, and continues to coordinate sessions without leaking
  either value

### Requirement: A support session proves MCP health

Readiness SHALL require both the OpenCode service and the support MCP integration
to be operational. A session selected with the support profile MUST be able to
invoke an MCP health or setup operation and receive facts from the configured
same-server endpoint before the integration is considered healthy.

#### Scenario: A support session starts healthy

- **WHEN** an authenticated client creates a session, selects the support profile,
  and requests OpenCode MCP setup or status
- **THEN** the MCP reports the expected running server, project context, provider
  availability, and a non-error result

#### Scenario: The MCP endpoint is unavailable

- **WHEN** the support MCP cannot authenticate to or query the declared OpenCode
  endpoint
- **THEN** readiness and the support-session health operation report failure
  rather than claiming that MCP support is usable

### Requirement: The support profile can view same-server sessions

The support profile SHALL be able to list and inspect sessions visible to the
same OpenCode server, including sessions created through the HTTP API, through
the support MCP, and from a terminal attached with `opencode attach`. Session
identity, title, status, directory, and available message history MUST correspond
to the server's runtime records.

#### Scenario: The support profile views an API-created session

- **WHEN** another client creates a session and sends a uniquely identifiable
  message on the same server
- **THEN** the support profile can discover that session and read the matching
  conversation through OpenCode MCP tools

#### Scenario: The support profile views a terminal-attached session

- **WHEN** a real terminal client runs `opencode attach` against the server and
  creates or continues a session with uniquely identifiable content
- **THEN** the support profile can discover that same session and inspect the
  content produced through the attached terminal

### Requirement: The support profile can start sessions

The support profile SHALL be able to create a new session on the same OpenCode
server and SHALL return a stable session identifier that can be inspected by
other clients. It SHALL also be able to start work in a new session with an
explicit enabled profile by passing that profile as the OpenCode agent. Unknown,
disabled, or disallowed profile names MUST be rejected without silently falling
back to another profile.

#### Scenario: The support profile starts an unprofiled session

- **WHEN** a support session invokes the OpenCode MCP session-creation workflow
  without a profile
- **THEN** the same server records a distinct session whose identifier and title
  are returned and discoverable

#### Scenario: The support profile starts a session with a profile

- **WHEN** a support session starts work with the name of another enabled
  declarative profile
- **THEN** the new session runs its first turn with that profile's model, rules,
  skills, MCP boundaries, and permissions

#### Scenario: The support profile requests an unavailable profile

- **WHEN** a support session requests an unknown or disabled profile for new work
- **THEN** session startup fails explicitly and no fallback-profile response is
  recorded

### Requirement: The support profile can exchange messages with another session

The support profile SHALL be able to send a message to an existing same-server
session, receive its correlated assistant response, and read subsequent messages
that another client sends to that session. Message ordering, roles, session
identity, and correlation MUST be preserved, and a timeout or failed turn MUST
remain distinguishable from a successful response.

#### Scenario: The support profile sends and receives a turn

- **WHEN** the support profile sends uniquely identifiable text to another
  session and waits for completion
- **THEN** OpenCode MCP returns the assistant response for that exact session and
  turn and the conversation contains both messages in order

#### Scenario: Another client continues the session

- **WHEN** an API or attached-terminal client sends a later message to the target
  session
- **THEN** the support profile can read the new user message and its correlated
  assistant response without creating a replacement session

### Requirement: Support-profile behavior is verified in a MicroVM

The change SHALL provide an executable MicroVM check that uses the packaged
`opencode-mcp`, a deterministic provider, the running OpenCode server, and a real
terminal attachment. The check MUST exercise MCP protocol calls through a
support-profile session rather than substituting direct HTTP calls for the
behavior under test.

#### Scenario: The support-profile integration check runs

- **WHEN** `nix build .#checks.x86_64-linux.opencode-mcp-support-profile --print-build-logs`
  runs
- **THEN** it boots the MicroVM and verifies healthy MCP startup, visibility of
  API and `opencode attach` sessions, unprofiled and explicitly profiled session
  creation, bidirectional message exchange, profile rejection, authentication
  rotation, and secret non-disclosure

### Requirement: Support-profile declarations have drift reverse configuration

Drift detection SHALL observe every supported support-profile enabled state,
generated name, model, tool-profile choice, MCP endpoint, package identity, and
permission attribute and SHALL produce a deterministic review-only declaration
candidate from runtime observation. It MUST report provenance, completeness,
unsupported state, ambiguity, and secret exclusions and MUST NOT mutate runtime,
credential, persistence, source, or version-control state.

#### Scenario: Support-profile runtime state drifts

- **WHEN** `nix build .#checks.x86_64-linux.opencode-mcp-support-profile-drift-reverse-configuration --print-build-logs`
  boots a MicroVM, changes observable support-profile state, and runs drift
  conversion
- **THEN** the candidate derives from that mutation, omits credentials, marks
  unresolved inputs and incompleteness explicitly, and reproduces represented
  support behavior in a second booted MicroVM after reviewed inputs are supplied

### Requirement: Running support profiles have live-capture reverse configuration

Live capture SHALL reconstruct every supported support-profile enabled state,
generated name, model, tool-profile choice, MCP endpoint, package identity, and
permission attribute from runtime facts. It MUST be deterministic, review-only,
secret-free, explicit about provenance and unresolved inputs, and MUST NOT claim
completeness for unavailable or unrepresentable state.

#### Scenario: A running support profile is captured

- **WHEN** `nix build .#checks.x86_64-linux.opencode-mcp-support-profile-live-capture-reverse-configuration --print-build-logs`
  boots a MicroVM, exercises cross-session behavior, and captures the running
  integration twice
- **THEN** both captures are stable and runtime-derived, credentials are excluded,
  limitations are explicit, and represented support behavior is verified in a
  second booted MicroVM after unresolved inputs are supplied
