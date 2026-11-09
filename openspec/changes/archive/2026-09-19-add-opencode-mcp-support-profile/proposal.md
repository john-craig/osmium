## Why

Operators need a bounded support profile that can inspect and coordinate other
OpenCode sessions on the same Osmium server without manually calling the HTTP
API. The upstream `opencode-mcp` server exposes these workflows over MCP, but it
is not currently packaged, configured, or verified as part of the declarative
OpenCode service.

## What Changes

- Add a disabled-by-default support-profile declaration that installs a pinned
  `opencode-mcp` package, registers it as a local MCP server, and exposes it only
  to the named support profile.
- Connect `opencode-mcp` back to the already-running authenticated OpenCode
  server with runtime-only credentials and automatic server startup disabled.
- Define a bounded full-tool policy that permits the support profile to inspect
  sessions, create sessions, select a declared profile for new work, and exchange
  messages with sessions on the same server.
- Add runtime health and readiness checks proving that the support profile and
  MCP connection are usable, not merely present in generated configuration.
- Add a MicroVM integration check that exercises cross-session visibility for
  API-created and terminal-attached sessions, unprofiled and profiled session
  creation, and bidirectional message exchange.
- Extend drift and live-capture reverse configuration for every new declarative
  support-profile attribute, with explicit package provenance, secret exclusion,
  and unresolved runtime inputs.
- Document enablement, profile permissions, credential handling, usage, and
  rollback.

## Capabilities

### New Capabilities

- `opencode-mcp-support-profile`: Declarative packaging, configuration, health,
  session coordination, and MicroVM verification for an OpenCode support profile
  backed by `AlaeddineMessadi/opencode-mcp`.

### Modified Capabilities

- `opencode-declarative-profiles`: Profiles gain a supported opinionated support
  profile whose MCP boundary permits same-server session coordination.
- `opencode-server-service`: Readiness and reverse configuration include the
  support profile, its local MCP process, and its runtime connection state.

## Impact

- Adds a pinned upstream source/package for `opencode-mcp` 3.x and Node.js 22 or
  newer; the package is not currently available as a nixpkgs attribute.
- Extends `services.osmium.opencodeServer` options, typed OpenCode configuration,
  runtime environment generation, readiness, observation, and drift conversion.
- Adds executable MicroVM checks and deterministic provider behavior for nested
  OpenCode session orchestration.
- Adds a local MCP process that can act on all sessions visible to the configured
  OpenCode server; access remains limited to the explicitly enabled support
  profile and its generated MCP tool namespace.
