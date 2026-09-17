## Context

The current Osmium service writes OpenCode configuration through Home Manager's
generic settings option and already tests authenticated session/message requests
against a deterministic OpenAI-compatible provider. It has no typed abstraction
for session-specific capability sets. See `proposal.md` for motivation and the
two delta specs for required behavior.

`github:albertov/opencode-nix` exposes a typed OpenCode schema and
`pkgs.lib.opencode.mkOpenCodeConfig`. Its current schema includes
`opencode.agent`, `opencode.skills.paths`, `opencode.mcp`, and global/per-agent
permissions. Skills are loaded globally by OpenCode, so per-profile availability
must be enforced through each generated agent's `permission.skill` map. MCP
servers are also registered globally, so their generated tool namespaces must be
denied by default and selectively allowed per profile.

The project rules require every new declarative attribute to support both drift
conversion and live capture, with separate booting MicroVM tests that prove the
candidate came from runtime observation and verify resulting behavior.

## Goals / Non-Goals

**Goals:**

- Provide stable named profiles selectable through OpenCode's message `agent`
  field.
- Compose profile rules, immutable skill sources, MCP servers, model settings,
  and permissions into one schema-validated OpenCode configuration.
- Enforce least-privilege skill and MCP availability between profiles.
- Preserve runtime-only handling and rotation of provider and MCP credentials.
- Test the full server-to-provider-to-MCP-to-provider-to-client turn in a
  booted MicroVM.
- Extend both reverse-configuration mechanisms for every added attribute.

**Non-Goals:**

- Invent a second profile protocol outside OpenCode's existing agent/session API.
- Add a general-purpose MCP implementation or depend on external MCP services in
  tests.
- Allow runtime mutation of declarative profiles through the OpenCode API.
- Put rule, skill, MCP, or provider secrets into Nix declarations or store paths.
- Replace the existing Osmium lifecycle, credential mount, persistence, and
  authenticated web-service ownership model with `opencode-nix`'s NixOS service
  module.

## Decisions

### Pin and use the opencode-nix configuration library, not its service module

Add an `opencode-nix` flake input pinned in `flake.lock` and apply its overlay so
`pkgs.lib.opencode.mkOpenCodeConfig` is available. Generate the final
`opencode.json` from composable typed modules and continue to run the existing
Home Manager-managed Osmium service.

This preserves Osmium's MicroVM mounts, impermanence, readiness, runtime
credential reconciliation, and user-service behavior while avoiding a local
copy of the upstream OpenCode schema. Importing the `opencode-nix` NixOS service
module instead was rejected because it would create overlapping service users,
state ownership, and lifecycle policy.

### Model a profile as a primary OpenCode agent

Expose a structure equivalent to:

```nix
services.osmium.opencodeServer = {
  skills.<name> = { path = ./skills/<name>; };
  mcpServers.<name> = { type = "local"; command = [ ... ]; };
  profiles.<name> = {
    enable = true;
    model = "local/mock";
    rules = [ "..." ];
    ruleFiles = [ ./rules/review.md ];
    skills = [ "review" ];
    mcpServers = [ "facts" ];
    permissions = { read = "allow"; };
  };
};
```

Each enabled profile becomes `opencode.agent.<name>` with `mode = "primary"`.
Its deterministic prompt concatenates ordered inline rules and immutable rule
files. The API creates a session, then sends each profiled turn to
`POST /session/:id/message` with `{"agent":"<name>", ...}`; no separate
Osmium session endpoint is introduced. Names use the subset accepted by both
Nix attribute paths and OpenCode agent identifiers, and all references are
checked at evaluation.

Treating profiles as separate OpenCode server instances was rejected because it
would duplicate state, ports, credentials, and sessions and would not meet the
requirement that a client select a profile for a session on one server.

### Use shared registries with generated per-agent deny-by-default permissions

Render each unique declared skill source once into `opencode.skills.paths` and
each MCP declaration once into `opencode.mcp`. For each profile, generate a
permission baseline that denies skills and MCP tool namespaces, then allows only
the referenced skills and MCP namespaces. Merge explicit profile permissions
only when they do not weaken the generated boundary; conflicting wildcard or
namespace rules fail evaluation.

The exact MCP tool-name prefix emitted by the pinned OpenCode version will be
captured in a focused evaluation/runtime fixture rather than guessed. A small
adapter in the module will translate a logical MCP server name to the observed
permission keys. This boundary is version-pinned with OpenCode and
`opencode-nix` and covered by the MicroVM test.

Loading a separate config per session was rejected because OpenCode loads one
server configuration and session agent selection already supplies the intended
isolation primitive.

### Keep secrets in the existing runtime environment file

Local MCP `environment` and remote MCP headers may contain OpenCode runtime
references such as `{env:MCP_TOKEN}` but must not contain credential literals.
The mounted server environment file remains the runtime source. Its existing
digest reconciliation restarts OpenCode whenever any value changes, so MCP
credential replacement follows the same changed-secret rotation path without a
new secret store. Generated config, observations, candidates, diagnostics, and
completion records retain references only.

### Build protocol-level mock provider and MCP fixtures

Extend the deterministic provider fixture to maintain a two-request state
machine:

1. On the initial chat-completion request, assert the selected profile's rules
   and expected MCP tool schema are present, then emit an OpenAI-compatible
   streamed tool call with fixed arguments.
2. After OpenCode invokes the tool, assert the next provider request contains
   the exact structured MCP tool result, then emit the fixed final response
   `profile-mcp-ok`.

Implement local mock MCP servers as small packaged Python stdio programs. They
will implement only the MCP JSON-RPC methods OpenCode exercises:
`initialize`, initialized notification handling, `tools/list`, and `tools/call`.
Each server exposes uniquely named deterministic tools, validates arguments and
optional runtime token, records calls outside the source tree, and returns fixed
structured content. No SDK download or external network is required.

The primary test will boot the actual MicroVM, authenticate to the running
OpenCode server, create a session with a profile, post a prompt, and assert the
final response plus both provider and MCP call traces. A second profile and MCP
server prove negative isolation by checking that a disallowed server receives no
call.

### Add three profile-specific booting checks

Register these checks:

- `nix build .#checks.x86_64-linux.opencode-server-profiles --print-build-logs`
  verifies evaluation failures, generated configuration, profile selection,
  rules and skills visibility, MCP allowlist isolation, credential references,
  and the complete tool-calling turn.
- `nix build .#checks.x86_64-linux.opencode-server-profiles-drift-reverse-configuration --print-build-logs`
  mutates observable runtime profile state, derives a candidate from that
  observation, and boots a candidate-configured MicroVM to verify behavior.
- `nix build .#checks.x86_64-linux.opencode-server-profiles-live-capture-reverse-configuration --print-build-logs`
  captures runtime profile state twice, verifies determinism and secret
  exclusion, and boots a candidate-configured MicroVM to verify behavior.

These are separate from the existing server checks so profile regressions and
reverse-conversion failures have focused derivations.

### Represent reverse configuration with explicit source classes

Observation records normalized profile identity, selected model, rule digests
and safe inline text, skill names and immutable store provenance, logical MCP
names and non-secret transport configuration, permissions, and enabled state.
Runtime environment values are always excluded. Host-only or source-level paths
that cannot be reconstructed are emitted as unresolved placeholders, which make
the candidate incomplete and activation-blocked until reviewed.

Drift compares this normalized runtime document with the normalized declaration.
Live capture starts only from runtime facts. Both outputs use stable key ordering
and identify the OpenCode and `opencode-nix` revisions that define their schema.

## Risks / Trade-offs

- **[OpenCode permission names for MCP tools may change]** -> Pin OpenCode and
  `opencode-nix`, derive names from an observed fixture, and fail focused tests on
  incompatible changes.
- **[Skills are globally loaded even when denied to a profile]** -> Enforce
  per-agent skill permissions and test cross-profile denial; document that the
  boundary is OpenCode authorization, not separate processes.
- **[Typed generated settings may conflict with the existing free-form settings
  option]** -> Normalize both through module composition and reject conflicts
  rather than defining precedence.
- **[A handwritten mock MCP server may diverge from the protocol]** -> Implement
  the smallest standards-compliant JSON-RPC exchange observed from the pinned
  client and assert initialization, discovery, and invocation transcripts.
- **[Rule text and skills enter the Nix store]** -> Define them as non-secret
  declarative content; reject runtime secret sources and direct operators to
  `{env:VAR}` references for credentials.
- **[Reverse capture cannot recover original source paths or Nix module
  composition]** -> Capture behavior and provenance, emit unresolved source
  placeholders, and never claim a complete activation-ready declaration.

## Migration Plan

1. Add and lock the `opencode-nix` input and overlay without enabling profiles.
2. Introduce registries and profile options disabled by an empty default, keeping
   current generated configuration behavior unchanged.
3. Compose existing settings through the typed generator and verify the current
   server checks before adding profile declarations.
4. Add profile generation, validation, permission boundaries, and the three
   profile checks.
5. Extend documentation and reverse-configuration formats with an explicit
   schema version transition.

Rollback removes profile declarations and the input integration, restoring the
previous free-form settings path. Existing persistent sessions and provider auth
remain intact; profile-derived agents disappear from new session selection, and
host-mounted credentials are not modified.
