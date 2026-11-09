## ADDED Requirements

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
