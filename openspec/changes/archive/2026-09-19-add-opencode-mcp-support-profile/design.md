## Context

The OpenCode service already renders named primary agents and local MCP servers
through the pinned typed generator, injects MCP secrets through `{env:VAR}`
references, and restarts OpenCode when its mounted environment file changes. The
new integration must compose with those mechanisms rather than introduce a
second session store or server process.

Upstream `AlaeddineMessadi/opencode-mcp` 3.0.0 is a Node.js 22+ stdio MCP server.
It expects an existing OpenCode HTTP endpoint by default, supports HTTP Basic
Auth through environment variables, and exposes session listing, inspection,
creation, workflow calls with an `agent` argument, message sending, waiting, and
conversation reads. It is not packaged in nixpkgs. The reviewed upstream source
revision is `6f1f62fd6c151377e09f4fe95bed58eb48c6196b`.

OpenCode starts local MCP commands as subprocesses. Therefore the support MCP can
call the parent OpenCode HTTP server without recursively starting another MCP or
OpenCode process, provided `OPENCODE_AUTO_SERVE=false` and the base URL points to
the existing guest listener.

## Goals / Non-Goals

**Goals:**

- Package and pin a reproducible `opencode-mcp` executable with vendored npm
  dependencies.
- Provide one disabled-by-default declarative shortcut that safely composes a
  support primary agent and same-server local MCP registration.
- Reuse the existing runtime credential and changed-secret reconciliation paths.
- Verify the real nested path: support session, provider tool request, OpenCode
  MCP subprocess, same OpenCode HTTP server, target session, and response.
- Prove attached-terminal sessions share the same session namespace.
- Preserve complete drift and live-capture coverage for all new attributes.

**Non-Goals:**

- Supporting a remote `opencode-mcp` transport or an MCP connected to a different
  OpenCode server.
- Automatically approving target-session permission or question requests.
- Isolating filesystem changes between sessions; upstream sessions share their
  declared project directory and normal OpenCode permission policy.
- Replacing the generic profile and MCP registries with support-specific data
  structures.
- Exposing provider-authentication administration or public session sharing as
  required support workflows.

## Decisions

### Pin and package upstream source directly

Add an `opencode-mcp` source input pinned to the reviewed revision and package
version 3.0.0 with `buildNpmPackage`, Node.js 22+, and a fixed npm dependency hash.
Expose the package internally to the OpenCode module rather than requiring a
nixpkgs attribute that does not exist.

Alternative: run `npx -y opencode-mcp`. Rejected because it performs mutable
network resolution at runtime, is not reproducible, and cannot be used in an
offline MicroVM check.

Alternative: copy the upstream implementation into Osmium. Rejected because it
would create an unnecessary fork and obscure package provenance.

### Generate an opinionated declaration over existing registries

Add `services.osmium.opencodeServer.supportProfile` with these declarative
attributes:

- `enable`, default `false`;
- `name`, default `support`;
- `mcpName`, default `opencode-support`;
- `model`, required when enabled;
- `toolProfile`, enum `full` or `essential`, default `full`;
- `package`, defaulting to the pinned package.

Enabling it synthesizes entries equivalent to `profiles.<name>` and
`mcpServers.<mcpName>` before conflict validation. The profile is a primary agent,
references only the generated MCP by default, and receives the normal generated
deny-by-default MCP and skill permissions. The `full` catalog is the default
because low-level session creation, inspection, and message tools are explicit
acceptance criteria; `essential` remains an operator choice with reduced tool
discovery and is not claimed to satisfy every full-catalog workflow.

Alternative: document a hand-authored generic profile and MCP declaration.
Rejected because packaging, endpoint derivation, runtime authentication,
readiness, reverse configuration, and safe defaults would remain duplicated and
unverified for every deployment.

### Derive the same-server endpoint and runtime environment

The generated local MCP command is the pinned `opencode-mcp` executable. Its
environment is generated as follows:

- `OPENCODE_BASE_URL=http://127.0.0.1:<guestPort>`;
- `OPENCODE_SERVER_USERNAME` from the non-secret declared server username;
- `OPENCODE_SERVER_PASSWORD={env:OPENCODE_SERVER_PASSWORD}`;
- `OPENCODE_AUTO_SERVE=false`;
- `OPENCODE_TOOL_PROFILE` from `supportProfile.toolProfile`;
- `OPENCODE_TASK_STORE` below the existing persistent OpenCode data directory.

The parent OpenCode service already receives the password from its runtime
environment file, so the local MCP subprocess inherits the current value and the
typed config contains only the exact environment reference. Password rotation
restarts OpenCode, which also replaces its MCP subprocesses and guarantees new
calls use the replacement value.

Alternative: add a second password file consumed by `opencode-mcp`. Rejected
because it duplicates a credential that already exists in the parent process and
creates divergent rotation state.

### Separate base readiness from support readiness

Keep the existing base server health result independently observable. When the
support profile is enabled, add a support readiness stage after base readiness.
The stage launches the packaged stdio MCP in a controlled probe, completes MCP
initialization, invokes `opencode_status` or `opencode_setup` against the
authenticated local endpoint, validates structured non-error output, and writes
only secret-free state. Overall Osmium readiness depends on this stage, while
diagnostics retain the distinction between base server health and support MCP
failure.

The primary integration test additionally selects the support agent in a real
OpenCode session and verifies the same operation through OpenCode's configured
MCP client. This avoids treating a standalone binary probe as proof that profile
tool routing works.

Alternative: rely on `opencode mcp list`. Rejected because a configured or
connected MCP entry does not prove its nested HTTP client can authenticate and
query the intended server.

### Drive cross-session tests through deterministic tool calls

Extend or add a deterministic OpenAI-compatible provider fixture that maps
explicit test prompts to one OpenCode MCP tool call at a time and validates the
returned structured result before producing a fixed final response. Record tool
names, arguments, results, agent identity, session identity, and ordering while
excluding environment values and authorization headers.

The MicroVM check will:

1. Boot the authenticated server with the support profile and a second ordinary
   profile.
2. Select the support profile and invoke setup/status to prove health.
3. Create an API session with a unique message, then use support MCP session and
   conversation tools to find and inspect it.
4. Start a real pseudo-terminal running `opencode attach` against the same server,
   create or continue a session, send unique content through the TUI, and prove
   the support profile sees the same session and content.
5. Use `opencode_session_create` for an empty session and verify its returned ID
   through an independent API query.
6. Use `opencode_ask`, `opencode_run`, or create-plus-message with `agent` set to
   the ordinary profile; verify the target provider receives that profile's
   distinctive rules and returns a fixed profile marker.
7. Request an unknown/disabled agent and verify explicit failure without a
   fallback completion.
8. Send a unique message into an existing target session through MCP, verify the
   exact assistant response, continue that session from the API and attached
   terminal, and read the ordered conversation back through MCP.
9. Rotate the server password and repeat an MCP operation, then scan generated
   state, process arguments, journals, transcripts, readiness state, observation,
   and drift output for both credential values.

The attached-terminal step uses an actual PTY controller such as `tmux` or
`python` plus `pty`, not a direct session API call. It invokes `opencode attach`
with runtime Basic Auth and records the resulting server session ID before
cross-checking it through MCP.

### Extend normalized state and both reverse paths

Add support-profile declaration and observation objects carrying enabled state,
names, model, tool profile, package identity/version/source revision, derived
endpoint identity, permission boundary, readiness, and MCP protocol/runtime
status. Credential values remain excluded; source/package overrides that cannot
be reconstructed become explicit unresolved inputs and force
`complete=false`/`activation_ready=false`.

Register separate executable checks:

- `opencode-mcp-support-profile-drift-reverse-configuration` mutates observable
  support state, derives a candidate from that mutation, verifies non-mutation
  and secret exclusion, supplies unresolved inputs, and boots a second MicroVM to
  verify represented behavior.
- `opencode-mcp-support-profile-live-capture-reverse-configuration` exercises the
  running MCP, captures twice, proves stable runtime provenance, supplies
  unresolved inputs, and boots a second MicroVM to verify represented behavior.

Alternative: infer support state only from the generated profile and generic MCP
maps. Rejected because this loses the operator's support-profile intent, package
provenance, tool-profile choice, and readiness status.

## Risks / Trade-offs

- [A support profile can act on every same-server session in its project scope]
  -> Keep it disabled by default, expose its MCP namespace only to the named
  profile, deny weakening permission merges, and document the trust boundary.
- [Nested support calls can target the support session itself and create loops]
  -> Tests use explicit target IDs; generated rules instruct the support profile
  not to delegate into its own active turn; timeouts remain bounded and visible.
- [Upstream tool names or schemas can change]
  -> Pin source and npm dependencies, assert required tool discovery in
  evaluation/runtime tests, and require an explicit dependency update to change
  the contract.
- [`opencode attach` is interactive and may be timing-sensitive]
  -> Drive it through a PTY with deterministic readiness markers and bounded
  waits, and correlate by unique session content rather than screen layout alone.
- [Support readiness performs a loopback call during startup]
  -> Order it strictly after base authenticated health and preserve separate base
  and support statuses for diagnosis.
- [Full tool discovery increases prompt/tool-schema size]
  -> Allow `essential` as an explicit optimization while testing and documenting
  that the full profile is required for the complete support contract.
- [Persisted upstream job metadata can outlive sessions]
  -> Store it under existing OpenCode persistence with private ownership and
  document upstream retention behavior; do not treat job records as session
  authority.

## Migration Plan

1. Add and lock the pinned source and package without enabling it by default.
2. Add support-profile options, generated config, validation, readiness, and
   reverse-state fields.
3. Run evaluation and all three support-profile MicroVM checks.
4. Operators enable the support profile with a model during a normal deployment;
   existing profiles and sessions remain unchanged.
5. Roll back by disabling `supportProfile.enable`. This removes the generated
   profile and MCP entry without deleting OpenCode sessions, provider auth, or
   upstream task-store data. Remove the private task-store directory separately
   only after confirming it is no longer needed.
