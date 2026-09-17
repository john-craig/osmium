## Why

The OpenCode server currently accepts a largely untyped settings object and has
no first-class way to declare reusable session profiles with bounded rules,
skills, and MCP tools. Declarative profiles are needed so operators can select a
known capability set for each session and verify the complete tool-calling path
without relying on external providers or MCP services.

## What Changes

- Add a pinned `opencode-nix` flake input and use its typed configuration
  generator for profile-related OpenCode configuration.
- Add named declarative profiles to `services.osmium.opencodeServer`, including
  profile rules, skill sources, allowed MCP servers, model selection, and
  permission policy.
- Render profiles as selectable primary OpenCode agents while keeping shared MCP
  server and skill definitions deduplicated and validated.
- Reject missing references, unsafe paths, secret-bearing declarative values,
  invalid profile names, and profiles that expose undeclared skills or MCP
  servers.
- Extend drift detection and live capture to report profile, rule, skill, and MCP
  configuration with explicit provenance, completeness, and secret handling.
- Add deterministic mock OpenAI-compatible provider and MCP implementations for
  MicroVM integration testing.
- Add an end-to-end MicroVM check that creates an authenticated server session
  with a selected profile, sends a prompt, observes the mock provider request an
  allowed MCP tool, verifies the mock MCP result is returned to the provider,
  and verifies the final expected assistant response.

## Capabilities

### New Capabilities

- `opencode-declarative-profiles`: Named OpenCode session profiles with typed
  rules, skills, MCP allowlists, permissions, profile selection, and end-to-end
  tool-call verification.

### Modified Capabilities

- `opencode-server-service`: Integrate pinned typed configuration generation,
  make profile selection observable in running sessions, and include profile
  attributes in drift and live-capture reverse configuration.

## Impact

- Adds and pins `github:albertov/opencode-nix` as a flake input following the
  repository's `nixpkgs` input where supported.
- Extends `modules/services/opencode-server.nix`, the generated OpenCode
  configuration, profile validation, reverse-configuration output, and README
  examples.
- Adds a dedicated booting MicroVM flake check, mock provider, and mock MCP
  servers; the existing OpenCode server checks remain required.
- Introduces a declarative session-facing API under
  `services.osmium.opencodeServer.profiles`, plus shared skill and MCP registries.
