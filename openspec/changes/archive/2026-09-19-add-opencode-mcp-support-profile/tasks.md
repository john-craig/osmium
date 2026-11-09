## 1. Pin and Package OpenCode MCP

Progress: The source is locked, the package uses Node.js 22 and a fixed npm
dependency hash, and the package-level protocol test is registered and passes.

- [x] 1.1 Add and lock the `AlaeddineMessadi/opencode-mcp` source at the reviewed
  revision, then verify `nix flake lock` and
  `nix flake check --no-build --no-update-lock-file` resolve it without changing
  unrelated inputs.
- [x] 1.2 Package `opencode-mcp` 3.0.0 with Node.js 22+ and a fixed npm dependency
  hash, then verify the package builds offline and its executable reports the
  expected version without invoking `npx` or downloading at runtime.
- [x] 1.3 Add a package-level MCP protocol test that initializes the stdio server,
  lists the required setup, status, session, workflow, message, wait, and
  conversation tools, and verifies `OPENCODE_AUTO_SERVE=false` never launches a
  child OpenCode server.

## 2. Declarative Support Profile

Progress: Support-profile options, generated profile/MCP wiring, runtime launcher
configuration, the exact runtime password reference, invalid/collision fixtures,
and unrelated-profile boundary coverage are implemented and passing.

- [x] 2.1 Add disabled-by-default `supportProfile` options for enablement, profile
  name, MCP name, model, tool profile, and package, then verify defaults, valid
  declarations, invalid names/models/tool profiles, and disabled output with
  evaluation fixtures.
- [x] 2.2 Compose enabled support declarations into the existing typed profile and
  MCP registries before conflict checks, then verify generated output contains one
  primary support agent and one local MCP server and rejects collisions with
  explicitly declared profiles or MCP servers.
- [x] 2.3 Generate the same-server endpoint and runtime environment with automatic
  startup disabled, a private persistent task store, and an exact
  `{env:OPENCODE_SERVER_PASSWORD}` reference, then verify evaluation and store
  scans contain no fixture credential values.
- [x] 2.4 Generate support rules and deny-by-default MCP permissions that permit
  only the configured OpenCode MCP namespace, then verify the support profile can
  discover required tools while an unrelated profile is denied and cannot leave
  an MCP call marker.
- [x] 2.5 Reject explicit permission merges that globally expose or otherwise
  weaken the generated support boundary, then verify each conflicting wildcard
  and namespace declaration fails with an actionable evaluation message.

## 3. Runtime Readiness and Credential Lifecycle

Progress: Support readiness is ordered after credential reconciliation and
authenticated base health. The launcher consumes a runtime-generated password
file, and the primary MicroVM verifies restart, replacement-password success,
old-password rejection, and secret-safe generated/reverse outputs.

- [x] 3.1 Add a support-readiness stage ordered after authenticated base server
  health that performs MCP initialization and a structured same-server status or
  setup call, then verify it distinguishes healthy, missing-package, wrong-endpoint,
  and failed-authentication states without secret-bearing diagnostics.
- [x] 3.2 Integrate support readiness into overall service readiness while
  retaining independently observable base health, then verify support failure
  blocks overall readiness without misreporting the OpenCode listener as down.
- [x] 3.3 Extend changed-server-password reconciliation to replace support MCP
  subprocesses and probes, then verify the replacement credential succeeds, the
  previous credential fails, and neither value appears in arguments, journals,
  generated state, readiness records, transcripts, observations, or drift output.

## 4. Deterministic Nested-Session Fixtures

Progress: The deterministic provider and MCP client fixtures support support
tool requests and structured results. The PTY-driven attached-terminal workflow
and API/terminal cross-session assertions now pass in the primary MicroVM check.

- [x] 4.1 Extend or add the deterministic provider fixture to request named
  OpenCode MCP tools, validate their structured results, and emit fixed completion
  markers, then verify transcripts preserve tool, argument, result, agent,
  session, and ordering data without authorization headers or environment values.
- [x] 4.2 Add a PTY-driven fixture for `opencode attach` that authenticates to the
  running server, creates or continues a terminal session, sends unique content,
  records its server session identity, and exits cleanly under bounded timeouts.
- [x] 4.3 Add fixture workflows for an ordinary profile with distinctive rules,
  an unknown or disabled profile, API-authored turns, MCP-authored turns, and
  terminal-authored turns, then verify each produces an unambiguous marker for
  cross-session assertions.

## 5. Support Profile MicroVM Integration

Progress: The primary check passes support readiness, MCP setup/status, ordinary
and support dispatch, unknown-profile rejection, MCP-authored turns, API and
attached-terminal session inspection, ordered conversation reads, observation,
drift, credential rotation, and secret non-disclosure.

- [x] 5.1 Add and register
  `checks.x86_64-linux.opencode-mcp-support-profile` with runtime-created server
  and provider credentials, the packaged MCP, deterministic provider, support
  profile, ordinary profile, and PTY tooling; verify the check boots and exercises
  the MicroVM rather than only evaluating options or building a closure.
- [x] 5.2 In the MicroVM, select the support profile and invoke setup/status through
  OpenCode's configured MCP client, then verify the session reports the expected
  same-server endpoint, project context, provider availability, and non-error
  health result.
- [x] 5.3 Create and message an API session, invoke a real `opencode attach`
  terminal session with unique content, and use support MCP list/get/conversation
  tools to verify both sessions and their messages are visible with matching IDs,
  directories, roles, and status.
- [x] 5.4 Use support MCP to create an unprofiled session and independently verify
  its returned ID and title through the OpenCode API, then start work with an
  explicit ordinary profile and verify its distinctive model/rules marker and
  bounded capabilities.
- [x] 5.5 Request an unknown or disabled profile through support MCP and verify an
  explicit error, absence of a fallback completion, and no silently remapped
  session behavior.
- [x] 5.6 Use support MCP to send a uniquely identified message into an existing
  session and receive its exact correlated response, continue that same session
  from the API and attached terminal, and verify MCP reads the complete ordered
  bidirectional conversation without creating a replacement session.
- [x] 5.7 Rotate the mounted server password and repeat session inspection and
  messaging through support MCP, then verify restart/reconnection, old-password
  rejection, replacement-password use, and secret absence across every required
  runtime and reverse-output surface.
- [x] 5.8 Run
  `nix build .#checks.x86_64-linux.opencode-mcp-support-profile --print-build-logs`
  and record a passing result for health, API and attached-terminal visibility,
  unprofiled/profiled creation, rejection, bidirectional messaging, isolation,
  rotation, and non-disclosure.

## 6. Drift Reverse Configuration

Progress: Runtime-mutated support state is observed into a review-only drift
candidate with provenance, explicit incompleteness, secret exclusion, and
non-mutation checks; the candidate is replayed in a second MicroVM.

- [x] 6.1 Extend normalized declaration and runtime observation with support
  enablement, names, model, tool profile, package version/source identity,
  endpoint identity, permission boundary, readiness, and MCP protocol status;
  verify deterministic fixtures cover changed, missing, ambiguous, unsupported,
  host-only, package-override, and secret state.
- [x] 6.2 Extend drift candidates with stable ordering, package/runtime provenance,
  schema revisions, completeness, exclusions, and activation-blocking unresolved
  inputs, then verify conversion is review-only and does not mutate services,
  sessions, credentials, persistence, sources, task records, or VCS state.
- [x] 6.3 Add and register
  `checks.x86_64-linux.opencode-mcp-support-profile-drift-reverse-configuration`;
  boot a MicroVM, mutate observable support state, prove the candidate derives
  from that mutation, omit secrets, supply unresolved inputs, and boot a second
  MicroVM to verify represented support health and cross-session behavior.
- [x] 6.4 Run
  `nix build .#checks.x86_64-linux.opencode-mcp-support-profile-drift-reverse-configuration --print-build-logs`
  and record that runtime-derived conversion, package provenance, secret omission,
  explicit incompleteness, non-mutation, and resulting behavior pass.

## 7. Live-Capture Reverse Configuration

Progress: Live capture derives support facts from the running service, proves
determinism and non-mutation over logical persistence, excludes secrets, reports
unresolved session/package inputs, and replays the captured endpoint/tool profile
in a second MicroVM.

- [x] 7.1 Extend live capture with every support-profile attribute and runtime
  status using observed profile, MCP, process, endpoint, package, and session
  facts rather than an independently authored equivalent fixture; verify stable
  ordering, provenance, scope, ambiguity, unsupported state, secret exclusions,
  and unresolved source/package inputs.
- [x] 7.2 Add and register
  `checks.x86_64-linux.opencode-mcp-support-profile-live-capture-reverse-configuration`;
  boot a MicroVM, exercise same-server session inspection and messaging, capture
  twice to prove deterministic runtime-derived output, supply unresolved inputs,
  and boot a second MicroVM to verify represented support behavior.
- [x] 7.3 Run
  `nix build .#checks.x86_64-linux.opencode-mcp-support-profile-live-capture-reverse-configuration --print-build-logs`
  and record that deterministic capture, package/runtime provenance, secret
  omission, explicit incompleteness, non-mutation, and resulting behavior pass.

## 8. Documentation and Final Verification

Progress: README documentation, formatting, flake evaluation, strict OpenSpec
validation, `git diff --check`, the primary support-profile MicroVM check, and
both reverse-configuration MicroVM checks pass.

- [x] 8.1 Document support-profile enablement, generated names, full versus
  essential tool discovery, same-server scope, profile selection, session
  inspection/creation/messaging examples, attached-terminal visibility, runtime
  credentials, rotation, persistence, reverse configuration, risks, and rollback;
  verify every documented option and command evaluates or runs against the module.
- [x] 8.2 Run `nix fmt`, `git diff --check`,
  `nix flake check --no-build --no-update-lock-file`, and
  `openspec validate add-opencode-mcp-support-profile --strict`, fixing all
  failures.
- [x] 8.3 Re-run the existing `opencode-server` and
  `opencode-server-profiles` checks plus all three new executable support-profile
  checks with `--print-build-logs`, and record every result before considering
  implementation complete.
