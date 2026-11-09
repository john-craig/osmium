## ADDED Requirements

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
