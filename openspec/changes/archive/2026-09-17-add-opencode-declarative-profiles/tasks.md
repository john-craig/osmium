## 1. Dependency and Typed Configuration Foundation

- [x] 1.1 Add and lock the `github:albertov/opencode-nix` flake input, make it
  follow the repository `nixpkgs` input where supported, apply its overlay only
  where required, and verify `nix flake lock` plus
  `nix flake check --no-build --no-update-lock-file` resolve the pinned typed
  configuration API.
- [x] 1.2 Route the existing OpenCode settings through
  `pkgs.lib.opencode.mkOpenCodeConfig` while preserving current server behavior,
  and verify the existing `opencode-server` MicroVM check and generated-config
  assertions pass without profiles enabled.
- [x] 1.3 Add evaluation fixtures proving compatible base settings compose with
  generated profile state while duplicate agents, MCP definitions, skill
  registries, or permission boundaries fail with actionable conflicts.

## 2. Declarative Profile Model

- [x] 2.1 Add disabled-by-default shared skill and MCP registries plus named
  `services.osmium.opencodeServer.profiles` options for enabled state, model,
  ordered inline rules, immutable rule files, skill references, MCP references,
  and permissions; verify valid declarations evaluate and invalid names, paths,
  transports, and missing references fail.
- [x] 2.2 Generate each enabled profile as a primary OpenCode agent with a stable
  name and deterministic ordered prompt, and verify generated configuration
  preserves rule ordering, file provenance, model selection, and identical output
  for identical declarations.
- [x] 2.3 Render each immutable skill source once through
  `opencode.skills.paths`, generate per-profile skill allowlists with a deny
  default, and verify one profile cannot invoke a skill reserved for another.
- [x] 2.4 Render local and remote MCP declarations through the pinned typed schema,
  derive the pinned OpenCode MCP tool permission namespaces, generate per-profile
  deny-by-default MCP permissions, and verify undeclared MCP tools are denied.
- [x] 2.5 Merge explicit profile permissions without permitting them to weaken
  generated skill or MCP boundaries, and verify wildcard and namespace conflicts
  fail evaluation rather than taking implicit precedence.
- [x] 2.6 Support runtime `{env:VAR}` references for MCP environment and header
  credentials while rejecting credential literals, and verify generated files,
  Nix store-facing derivations, units, observations, and diagnostics contain no
  fixture secret values.

## 3. Session Selection and Credential Lifecycle

- [x] 3.1 Verify authenticated `POST /session/:id/message` requests can select
  an enabled profile through the OpenCode agent field, unknown or disabled
  profiles are rejected, and the selected profile remains active for subsequent
  message turns unless explicitly switched.
- [x] 3.2 Extend the existing environment-file digest reconciliation to cover MCP
  runtime credentials, then verify a changed secret-file value restarts OpenCode,
  the replacement credential is consumed by a later MCP call, the previous value
  no longer succeeds, and neither value appears in completion records or logs.
- [x] 3.3 Define and test behavior for sessions that reference a profile removed
  by a later deployment, ensuring new sessions cannot select it and existing
  sessions are not silently remapped.

## 4. Deterministic Provider and MCP Fixtures

- [x] 4.1 Package a deterministic local stdio MCP fixture implementing
  `initialize`, initialized notification handling, `tools/list`, and `tools/call`;
  verify a protocol test observes tool discovery, validated arguments, fixed
  structured results, optional runtime-token validation, and a durable call
  marker.
- [x] 4.2 Add at least two mock MCP server instances with distinct tools and call
  markers so profile isolation can be observed, and verify only the server
  allowed by the selected profile receives a request.
- [x] 4.3 Extend the OpenAI-compatible mock provider into a deterministic two-step
  tool-call state machine that first emits a streamed MCP tool call and then
  validates the returned tool result before emitting `profile-mcp-ok`; verify its
  transcript records the selected profile rules, advertised tool schema, tool
  result, and final response without credentials.

## 5. Profile MicroVM Integration

- [x] 5.1 Add and register `checks.x86_64-linux.opencode-server-profiles` with
  runtime-created credentials, rules, skills, mock provider, and mock MCP
  processes; verify the check boots and exercises the MicroVM rather than only
  evaluating options or building a closure.
- [x] 5.2 In the profile check, authenticate to the running OpenCode server, create
  a session with a declared profile, send a prompt, verify the provider requests
  the expected MCP tool, verify OpenCode invokes the mock MCP and returns its
  structured result to the provider, and assert the API response contains
  `profile-mcp-ok`.
- [x] 5.3 In the same check, start sessions for profiles with different rule,
  skill, and MCP allowlists and verify selected capabilities are available while
  cross-profile skill and MCP requests are denied and leave no disallowed call
  marker.
- [x] 5.4 In the same check, replace the MCP runtime token in the mounted
  environment file and verify changed-secret reconciliation, service restart,
  successful use of the replacement, rejection of the previous token, and secret
  absence from generated state, process arguments, journals, transcripts, and
  reverse outputs.
- [x] 5.5 Run
  `nix build .#checks.x86_64-linux.opencode-server-profiles --print-build-logs`
  and record a passing end-to-end result covering session selection, provider
  tool calls, MCP invocation, final response, isolation, and rotation.

## 6. Drift Reverse Configuration

- [x] 6.1 Extend normalized declaration and runtime observation with every
  supported profile enabled state, model, ordered rule, skill reference, MCP
  reference, and permission attribute; verify deterministic fixtures cover
  changed, missing, ambiguous, unsupported, host-only, and secret state.
- [x] 6.2 Extend drift candidates with stable profile ordering, source provenance,
  schema revisions, completeness, exclusions, and activation-blocking unresolved
  source inputs, and verify conversion remains review-only and does not mutate
  service, credential, persistence, source, or VCS state.
- [x] 6.3 Add and register
  `checks.x86_64-linux.opencode-server-profiles-drift-reverse-configuration`;
  boot a MicroVM, introduce observable profile drift, prove the candidate derives
  from that mutation, omit secrets, supply unresolved inputs, and boot a second
  MicroVM to verify the represented profile behavior.
- [x] 6.4 Run
  `nix build .#checks.x86_64-linux.opencode-server-profiles-drift-reverse-configuration --print-build-logs`
  and record that runtime-derived conversion, secret omission, explicit
  incompleteness, non-mutation, and resulting profile behavior pass.

## 7. Live-Capture Reverse Configuration

- [x] 7.1 Extend live capture with every supported profile enabled state, model,
  ordered rule, skill reference, MCP reference, and permission attribute using
  runtime facts rather than an independently authored equivalent fixture; verify
  stable ordering, provenance, scope, ambiguity, unsupported-state reporting,
  secret exclusions, and unresolved source placeholders.
- [x] 7.2 Add and register
  `checks.x86_64-linux.opencode-server-profiles-live-capture-reverse-configuration`;
  boot a MicroVM, exercise a selected profile and MCP tool, capture twice to prove
  deterministic output, prove the candidate derives from runtime observation,
  supply unresolved inputs, and boot a second MicroVM to verify represented
  profile behavior.
- [x] 7.3 Run
  `nix build .#checks.x86_64-linux.opencode-server-profiles-live-capture-reverse-configuration --print-build-logs`
  and record that deterministic runtime capture, secret omission, explicit
  incompleteness, non-mutation, and resulting profile behavior pass.

## 8. Documentation and Final Verification

- [x] 8.1 Document a complete profile example with ordered rules, immutable skill
  sources, local and remote MCP declarations, per-profile allowlists, runtime MCP
  credential references, authenticated session creation, profile switching,
  rotation, reverse configuration, and rollback; verify every documented option
  and command evaluates against the module.
- [x] 8.2 Run `nix fmt`, `git diff --check`,
  `nix flake check --no-build --no-update-lock-file`, and
  `openspec validate add-opencode-declarative-profiles --strict`, fixing all
  failures.
- [x] 8.3 Re-run the existing `opencode-server` check and all three new executable
  profile checks with `--print-build-logs` after final changes, and record every
  result before considering implementation complete.
