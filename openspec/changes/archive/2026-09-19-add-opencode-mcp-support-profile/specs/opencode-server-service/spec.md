## ADDED Requirements

### Requirement: Server readiness includes support MCP usability

When the support profile is enabled, the server SHALL report ready only after the
OpenCode user service is authenticated and a support-profile MCP operation can
query that same server. Readiness MUST distinguish a configured MCP entry from a
working authenticated MCP connection.

#### Scenario: Support MCP is operational

- **WHEN** OpenCode is healthy and the support MCP successfully reports status
  from the same authenticated endpoint
- **THEN** server readiness includes a healthy support-profile integration state

#### Scenario: Support MCP cannot query OpenCode

- **WHEN** the MCP process is missing, exits, targets another endpoint, or cannot
  authenticate
- **THEN** support readiness fails with a non-secret diagnostic while base server
  health remains independently observable

### Requirement: Server reverse configuration includes support MCP state

The server's drift and live-capture paths SHALL include all supported declarative
support-profile and OpenCode MCP attributes. Both paths MUST preserve package and
runtime provenance, completeness, ambiguity, unsupported-state, non-mutation,
review-only, and secret-exclusion guarantees.

#### Scenario: Server drift includes support MCP state

- **WHEN** support-profile or MCP runtime state differs from the declaration and
  server drift conversion runs
- **THEN** the candidate includes observable non-secret state and marks package,
  host-only, credential, or source inputs unresolved when they cannot be safely
  reconstructed

#### Scenario: Server capture includes support MCP state

- **WHEN** live capture observes a running support profile and its MCP connection
- **THEN** output includes deterministic runtime-derived support state without
  credential values and without claiming completeness for unobservable inputs
