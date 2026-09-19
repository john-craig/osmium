# opencode-declarative-profiles Specification

## Purpose

Provide reproducible named OpenCode session profiles whose rules, skills, MCP
tools, model, and permissions are explicitly declared and testable as a bounded
capability set.

## Requirements

### Requirement: Profiles are fully declarative and selectable

The service SHALL support named profiles that declare a model, ordered rules,
available skills, available MCP servers, and tool permissions. Each enabled
profile SHALL be exposed as a selectable primary OpenCode agent, and a client
MUST be able to select it on a server message request. Profile names and
references MUST be stable and deterministic.

#### Scenario: A client starts a profiled session

- **WHEN** an authenticated client sends a message with the name of an enabled
  profile
- **THEN** the session uses that profile's model, rules, skills, MCP servers, and
  permissions for subsequent turns

#### Scenario: A client selects an unknown profile

- **WHEN** an authenticated client requests a profile that is absent or disabled
- **THEN** the server rejects the selection and does not silently use another
  profile

### Requirement: Profile rules are ordered and reproducible

Each profile SHALL accept an ordered set of non-secret rule texts or immutable
rule-file references. The generated profile instructions MUST preserve declared
order, MUST produce identical content for identical declarations, and MUST
identify rule provenance without embedding runtime secrets.

#### Scenario: Multiple rules are declared

- **WHEN** a profile declares more than one rule
- **THEN** the selected profile receives every rule in declaration order with
  deterministic separators and provenance

#### Scenario: A rule source is unsafe

- **WHEN** a rule references a missing, mutable runtime, secret-bearing, or
  otherwise unsupported source
- **THEN** evaluation fails with an actionable diagnostic rather than generating
  an incomplete profile

### Requirement: Skills are registered once and allowed per profile

The service SHALL support declarative skill sources and SHALL make each skill
available only to profiles that reference it. A profile MUST deny undeclared
skills even when those skills are loaded for another profile. Missing, duplicate,
ambiguous, or unsafe skill definitions and references MUST fail evaluation.

#### Scenario: A profile invokes an allowed skill

- **WHEN** a selected profile requests a skill listed in its declaration
- **THEN** OpenCode loads the declared immutable skill content and permits the
  invocation

#### Scenario: A profile requests another profile's skill

- **WHEN** a selected profile requests a skill that exists globally but is not in
  its allowlist
- **THEN** OpenCode denies the invocation without exposing the skill content

### Requirement: MCP servers are registered once and bounded per profile

The service SHALL support typed local and remote MCP server declarations and
SHALL expose each server's tools only to profiles that reference that server.
Profiles MUST deny MCP tool namespaces that are not declared for them. MCP
commands, endpoints, environment references, timeouts, and enabled state MUST be
validated, and secret values MUST use runtime references rather than literal Nix
values.

#### Scenario: A profile invokes an allowed MCP tool

- **WHEN** the selected profile and provider request a tool from an allowed,
  healthy MCP server
- **THEN** OpenCode invokes that MCP server and returns its structured result to
  the provider

#### Scenario: A profile requests a disallowed MCP tool

- **WHEN** the selected profile requests a tool from an MCP server outside its
  allowlist
- **THEN** OpenCode denies the invocation and the disallowed MCP server observes
  no request

#### Scenario: MCP authentication changes at runtime

- **WHEN** an MCP declaration uses a runtime environment reference and the
  mounted environment file changes to a valid replacement value
- **THEN** credential reconciliation restarts OpenCode and later MCP operations
  consume the replacement without storing either secret in generated config or
  reconciliation records

### Requirement: Profile configuration is schema validated

Generated OpenCode configuration SHALL be produced through a pinned typed schema
that covers agents, skills, MCP servers, and permissions. Invalid combinations,
unknown references, duplicate generated names, unsupported transports, and
permission conflicts MUST fail evaluation before the server starts.

#### Scenario: A complete profile evaluates

- **WHEN** all profile references and typed settings are valid
- **THEN** evaluation produces one deterministic OpenCode configuration with the
  profile represented as a primary agent

#### Scenario: A profile references missing resources

- **WHEN** a profile names a skill or MCP server that is not declared
- **THEN** evaluation fails and identifies the profile and unresolved reference

### Requirement: The support profile preserves profile boundaries

The declarative profile system SHALL generate the support profile as a primary
agent with access to only the configured OpenCode MCP namespace and any other
capabilities explicitly declared for it. Enabling support MUST NOT grant
OpenCode MCP tools to unrelated profiles, and explicit permissions MUST NOT
weaken the generated boundary.

#### Scenario: The support profile invokes OpenCode MCP

- **WHEN** a selected support profile requests an allowed `opencode-mcp` tool
- **THEN** OpenCode invokes the same-server MCP process and returns its structured
  result

#### Scenario: Another profile requests OpenCode MCP

- **WHEN** a profile that does not reference the support MCP requests one of its
  tools
- **THEN** OpenCode denies the request and no support MCP operation is performed

#### Scenario: An explicit permission weakens support isolation

- **WHEN** a declaration attempts to allow the support MCP namespace globally or
  for a profile outside its allowlist
- **THEN** evaluation fails with an actionable permission-boundary conflict

### Requirement: Profile behavior is verified end to end in a MicroVM

The change SHALL provide an executable MicroVM check using deterministic mock
provider and MCP implementations. The mock provider SHALL implement the provider
tool-call protocol, and the mock MCP servers SHALL implement sufficient MCP
initialization, tool discovery, and tool invocation behavior to exercise the
running OpenCode server without external network services.

#### Scenario: Mock provider invokes a profiled MCP tool

- **WHEN** `nix build .#checks.x86_64-linux.opencode-server-profiles --print-build-logs`
  boots the MicroVM, creates an authenticated session with a declared profile,
  and sends a prompt to the mock provider
- **THEN** the provider requests the expected allowed MCP tool, OpenCode invokes
  the mock MCP server, the provider receives the expected tool result, and the
  session returns the expected final assistant response

#### Scenario: Profile isolation is exercised

- **WHEN** the MicroVM check starts sessions with profiles having different skill
  and MCP allowlists
- **THEN** each session exposes its declared capabilities and rejects an MCP tool
  and skill reserved for the other profile

### Requirement: Profile declarations support drift reverse configuration

Drift detection SHALL observe every supported profile rule, skill reference, MCP
reference, model, enabled state, and permission attribute and SHALL produce a
review-only declaration candidate from the runtime observation. It MUST report
provenance, completeness, ambiguity, unsupported state, and secret exclusions,
and MUST NOT mutate the server or source state.

#### Scenario: Runtime profile configuration drifts

- **WHEN** `nix build .#checks.x86_64-linux.opencode-server-profiles-drift-reverse-configuration --print-build-logs`
  boots a MicroVM, changes an observable profile attribute at runtime, and runs
  drift conversion
- **THEN** the generated candidate is derived from that observation, omits
  secrets, records unresolved inputs, and reproduces the represented profile
  behavior when reviewed inputs are supplied in a second booted MicroVM

### Requirement: Running profiles support live-capture reverse configuration

Live capture SHALL reconstruct every supported profile rule, skill reference, MCP
reference, model, enabled state, and permission attribute from runtime facts. It
MUST be deterministic, review-only, secret-free, explicit about unresolved host
or credential inputs, and MUST NOT claim completeness for unavailable or
unrepresentable state.

#### Scenario: Running profiles are captured

- **WHEN** `nix build .#checks.x86_64-linux.opencode-server-profiles-live-capture-reverse-configuration --print-build-logs`
  boots a MicroVM and captures selected profile behavior and configuration
- **THEN** the candidate is proven to derive from runtime observation, repeated
  capture is stable, secrets are excluded, and the represented profile behavior
  is verified in a second booted MicroVM after unresolved inputs are supplied
