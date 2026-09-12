## 1. Declarative Credential Model

- [x] 1.1 Define typed `services.osmium.gitea.credentials` options for personal
  tokens, repository deploy keys, OAuth applications, and capability-gated OAuth tokens;
  verify valid declarations evaluate and invalid kinds, duplicate identities,
  missing fields, unsupported scopes/flows, and ambiguous owners fail before
  service activation
- [x] 1.2 Define output-file options for secret path, public metadata path,
  owner, group, mode, safe-area validation, and persistence; verify evaluated
  configuration contains only references and metadata, never secret contents
- [x] 1.3 Add assertions linking credentials to declared or existing users and
  repositories and preventing organizational credentials or implicit
  administrator privileges; verify actionable evaluation failures

## 2. Runtime Provisioning And Secure Delivery

- [x] 2.1 Implement the ordered runtime reconciliation service using the
  existing administrator credential lifecycle; verify it waits for Gitea and
  reads provisioning credentials only at runtime
- [x] 2.2 Implement personal-token creation, lookup, scope verification, and
  one-time secret delivery; verify permitted and forbidden API operations and
  no duplicate token after reconciliation restart
- [x] 2.3 Implement runtime SSH keypair generation, repository deploy-key
  registration, read/write mode handling, lookup, and private-key delivery;
  verify Git clone/push behavior matches the declared mode
- [ ] 2.4 Implement OAuth application registration and capability-gated
  non-interactive token issuance; for Gitea 1.27, explicitly reject the
  interactive authorization-code flow without mutation, and verify client
  metadata, unsupported-flow handling, and one-time secret delivery against
  the installed API
- [ ] 2.5 Implement atomic protected output writes and public/private output
  separation; verify ownership, mode, persistence, temporary-file cleanup,
  process-argument safety, and absence of values from logs

## 3. Identity Ledger And Revocation

- [ ] 3.1 Implement a versioned persistent non-secret credential ledger storing
  declaration/resource identity, Gitea IDs or public fingerprints, normalized
  metadata, and output metadata; verify no secret or reversible secret digest
  enters the ledger
- [ ] 3.2 Implement restart reconciliation and lost-output handling; verify
  existing credentials and outputs are reused, missing outputs fail closed, and
  no replacement credential is silently created
- [ ] 3.3 Implement declaration-removal detection and kind-specific revocation;
  verify removed managed credentials are revoked and outputs removed while
  unmanaged or identity-conflicted credentials remain untouched
- [ ] 3.4 Implement retryable failure state for incomplete creation, output
  failure, and revocation failure; verify failed operations are visible and do
  not record false success

## 4. Drift And Live Reverse Configuration

- [ ] 4.1 Extend normalized Gitea observations with credential kind, stable
  owner/resource, scopes, access mode, OAuth metadata, IDs/fingerprints,
  managed status, provenance, and redacted secret-presence markers; verify API
  pagination/order does not change normalized output
- [ ] 4.2 Extend drift detection to classify credential additions, removals,
  metadata changes, identity conflicts, unsupported fields, and unobservable
  secret state; verify reports are read-only and omit values, hashes, and
  private keys
- [ ] 4.3 Extend review-only export conversion with explicit output-file
  requirements, completeness, provenance, and unresolved-secret findings;
  verify repeated conversion is deterministic and incomplete candidates cannot
  pass activation readiness
- [ ] 4.4 Implement live credential capture and conversion from the running
  Gitea API; verify externally created credentials produce safe candidates,
  require operator-selected output paths, and never invent or emit secrets
- [ ] 4.5 Verify drift and live capture do not adopt, revoke, modify Gitea,
  write Nix source, alter ledger state, or activate configuration

## 5. Credential MicroVM Integration

- [ ] 5.1 Add flake check `gitea-credentials` that boots the Gitea MicroVM,
  provisions a user token, repository deploy key, and OAuth application, and
  verifies the installed version's unsupported OAuth token flow without
  mutation; verify runtime access, scopes, output files, permissions, and
  secret omission; execute with `nix build
  .#checks.x86_64-linux.gitea-credentials --print-build-logs`
- [ ] 5.2 In `gitea-credentials`, restart the MicroVM and verify credential IDs,
  public fingerprints, output values, and access behavior remain unchanged with
  no duplicates; remove a declaration and verify only the managed credential is
  revoked and its output removed
- [ ] 5.3 Add separate flake check
  `gitea-credential-drift-reverse-configuration` that mutates credential
  metadata in a running MicroVM, converts the exact runtime drift observation,
  consumes the generated candidate, and verifies metadata behavior, secret
  omission, completeness, and non-mutation; execute with `nix build
  .#checks.x86_64-linux.gitea-credential-drift-reverse-configuration
  --print-build-logs`
- [ ] 5.4 Add separate flake check
  `gitea-credential-live-capture-reverse-configuration` that externally creates
  supported credentials, captures the running Gitea service, converts that exact
  artifact, and verifies the resulting candidate behavior without an
  independently authored equivalent fixture; execute with `nix build
  .#checks.x86_64-linux.gitea-credential-live-capture-reverse-configuration
  --print-build-logs`
- [ ] 5.5 Verify the MicroVM checks cover unsupported OAuth capability, missing
  output, unsafe output paths, failed revocation, unrelated credentials,
  persistence, and absence of secrets from evaluated configuration, state,
  diagnostics, and generated reverse-configuration artifacts

## 6. Documentation And Final Verification

- [ ] 6.1 Document credential declaration shapes, supported Gitea versions and
  scopes, user/repository ownership, OAuth flow limitations, output protection,
  persistence, one-time generation, lost-output recovery, revocation, and the
  explicit absence of rotation
- [ ] 6.2 Document drift and live-capture schemas, provenance, completeness,
  unresolved secret requirements, review-only behavior, and non-adoption rules
- [ ] 6.3 Run `nix fmt` and verify no formatting changes remain
- [ ] 6.4 Run `openspec validate gitea-declarative-credentials --strict` and
  verify the change passes strict validation
- [ ] 6.5 Run `nix flake check --no-build --no-update-lock-file` and verify all
  outputs evaluate
- [ ] 6.6 Execute all three dedicated credential MicroVM checks and report each
  result
