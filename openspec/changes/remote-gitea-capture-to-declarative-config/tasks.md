## 1. Capture Contract And Fixtures

- [ ] 1.1 Define the versioned remote capture artifact schema for provenance,
  adapter identity, normalized service settings, identities, persistence,
  secret references, probe results, findings, completeness, and stable statuses
  and verify valid, partial, malformed, and unknown-version fixtures
- [ ] 1.2 Define canonical serialization, stable identity keys, origin markers,
  host identity redaction, size limits, and sensitive-field filtering and verify
  repeated normalization is byte-for-byte deterministic and credential-free
- [ ] 1.3 Define the adapter/probe interface and allowlisted probe vocabulary,
  including bounded output, failure phases, and unsupported-platform results,
  and verify arbitrary command or path input cannot be executed

## 2. Remote NixOS Discovery

- [ ] 2.1 Implement SSH transport configuration with host-key verification,
  operator-managed credentials, bounded timeouts, and redacted diagnostics and
  verify unreachable, authentication, timeout, and host-key failures are
  operational errors without artifacts containing credentials
- [ ] 2.2 Implement the standard NixOS adapter to discover the Gitea service
  user, state directory, configuration paths, endpoint, persistence paths,
  service settings, and adapter/version facts using read-only probes
- [ ] 2.3 Implement read-only Gitea observation through the API and/or local
  service interfaces for users, organizations, ownership, administrator status,
  external identities, and supported metadata, and verify pagination and API
  ordering cannot affect normalized output
- [ ] 2.4 Record probe provenance, missing optional probes, unsupported fields,
  inconsistent observations, and source generation details and verify partial
  captures cannot claim completeness

## 3. Conversion To Mythoclast Configuration

- [ ] 3.1 Convert a complete capture into deterministic Mythoclast Gitea user,
  organization, service-setting, and persistence declarations using stable local
  keys and verify the rendered candidate is valid Nix-shaped output
- [ ] 3.2 Convert safe secret references without reading secret bytes and emit
  explicit unresolved runtime secret-file requirements when references are not
  supplied; verify passwords, hashes, tokens, and secret contents never appear
  in artifacts, output, or diagnostics
- [ ] 3.3 Classify administrators, unsafe names, ambiguous owners, external
  identity records, unsupported settings, repositories, and other omitted state
  with stable machine-readable findings and verify incomplete candidates fail
  default activation/readiness checks
- [ ] 3.4 Preserve capture and conversion as separate non-mutating commands and
  verify they do not write remote state, local Nix files, running configuration,
  or version-control state

## 4. Future Adapter Boundary

- [ ] 4.1 Document and implement adapter capability/version discovery so future
  Linux adapters emit the same capture schema and explicitly report omissions
- [ ] 4.2 Add a synthetic adapter fixture and contract tests proving transport,
  normalization, findings, secret filtering, and conversion are independent of
  NixOS-specific discovery

## 5. Integration Verification

- [ ] 5.1 Add a remote NixOS/Gitea integration test node and verify SSH capture
  discovers the running service and externally created safe identities
- [ ] 5.2 Verify the remote node's Gitea records, configuration, persistence,
  and service lifecycle remain unchanged after capture and conversion
- [ ] 5.3 Verify generated output is deterministic, secret-free, contains
  supported Mythoclast declarations, and carries unresolved or unsupported state
  explicitly
- [ ] 5.4 Feed the generated candidate into a separate Mythoclast evaluation or
  MicroVM workflow and verify the resulting users and organizations behave as
  declared without using an independently authored equivalent fixture
- [ ] 5.5 Exercise unreachable host, unsafe probe output, redacted credentials,
  ambiguous ownership, unsupported settings, partial capture, and future
  adapter capability cases with exact statuses and no mutation

## 6. Documentation And Final Verification

- [ ] 6.1 Document SSH trust and privilege requirements, supported NixOS layouts,
  capture scope, artifact review, secret handling, completeness, conversion,
  unsupported state, and activation boundaries
- [ ] 6.2 Run `nix fmt` and verify no formatting changes remain
- [ ] 6.3 Run `openspec validate remote-gitea-capture-to-declarative-config --strict`
  and verify the change passes strict validation
- [ ] 6.4 Run `nix flake check --no-build --no-update-lock-file` and verify all
  outputs evaluate
- [ ] 6.5 Run the dedicated remote capture integration check and report the
  command and behavior verified
