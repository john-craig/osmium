## 1. Declarative Repository Model

- [ ] 1.1 Define repository option schema for stable local keys, user or
  organization ownership, repository name, supported metadata, and explicit
  content-scope boundaries; verify valid declarations evaluate and duplicate,
  unsafe, unavailable-owner, and unsupported-value declarations fail
- [ ] 1.2 Add repository persistence and runtime credential references without
  embedding secret contents; verify evaluated configuration and persistent
  metadata contain paths or non-reversible markers only
- [ ] 1.3 Add repository reconciliation after owner identities are available;
  verify creation, idempotent restart, metadata updates, owner conflict
  rejection, and non-destructive declaration removal through unit/API tests

## 2. Drift Detection And Conversion

- [ ] 2.1 Extend normalized Gitea drift observation to include user-owned and
  organization-owned repositories with stable owner/name identity and supported
  metadata; verify pagination and API ordering do not change the normalized
  result
- [ ] 2.2 Compare declared repository attributes with observed values and emit
  deterministic per-attribute drift records; verify additions, removals,
  metadata changes, owner conflicts, and unsupported fields are classified
- [ ] 2.3 Convert repository drift into review-only Mythoclast declarations;
  verify repeated conversion is byte-for-byte deterministic and never mutates
  Gitea, Nix source, adoption state, or version-control state
- [ ] 2.4 Add completeness, provenance, ambiguity, content-scope, and sensitive
  field handling; verify incomplete candidates cannot pass default readiness and
  no passwords, tokens, deploy keys, webhook secrets, or repository contents
  appear in output or diagnostics

## 3. Live Capture And Conversion

- [ ] 3.1 Implement live repository capture from the running Gitea API with
  explicit capture scope, provenance, pagination, capability facts, and
  completeness status; verify missing pages or required fields produce explicit
  incomplete findings
- [ ] 3.2 Convert live capture output into the same deterministic Mythoclast
  repository declaration shape used by drift conversion; verify user and
  organization ownership is preserved and API ordering cannot affect output
- [ ] 3.3 Verify live capture and conversion are review-only and consume runtime
  credentials without exposing their values or writing any remote or local
  service state

## 4. Drift Reverse-Configuration MicroVM

- [ ] 4.1 Add flake check
  `gitea-repository-drift-reverse-configuration` that boots a Gitea MicroVM
  with declared repository metadata and verifies the service is reachable
- [ ] 4.2 In that MicroVM mutate repository metadata externally, run the live
  drift detector, and verify the drift artifact records the observed change and
  preserves repository content and ownership
- [ ] 4.3 Convert the runtime-generated drift into a candidate, feed that exact
  candidate through a separate Mythoclast evaluation/reconciliation path, and
  verify the repository behavior and metadata; do not use an independently
  authored equivalent fixture
- [ ] 4.4 Verify the drift path's secret omission, incomplete/unsupported state,
  owner conflict, deterministic output, and non-mutation guarantees in the
  MicroVM; execute `nix build
  .#checks.x86_64-linux.gitea-repository-drift-reverse-configuration
  --print-build-logs`

## 5. Live-Capture Reverse-Configuration MicroVM

- [ ] 5.1 Add separate flake check
  `gitea-repository-live-capture-reverse-configuration` that boots a running
  Gitea MicroVM and externally creates repositories owned by a user and an
  organization
- [ ] 5.2 Capture the running service and verify the artifact contains the
  runtime-created repositories, correct owner references, supported metadata,
  provenance, and deterministic ordering
- [ ] 5.3 Convert the runtime-generated capture artifact and feed that exact
  candidate into a separate Mythoclast evaluation/reconciliation path; verify
  equivalent repository metadata without an independently authored capture
  fixture
- [ ] 5.4 Verify the live-capture path's secret omission, incomplete/unsupported
  state, non-mutation behavior, and repeatability in the MicroVM; execute `nix
  build
  .#checks.x86_64-linux.gitea-repository-live-capture-reverse-configuration
  --print-build-logs`

## 6. Documentation And Final Verification

- [ ] 6.1 Document repository declaration fields, owner dependencies, supported
  metadata, non-destructive lifecycle, content boundary, credentials, drift
  conversion, live capture, completeness, review, and activation
- [ ] 6.2 Run `nix fmt` and verify formatting leaves no changes
- [ ] 6.3 Run `openspec validate gitea-declarative-repositories --strict` and
  verify the change passes strict validation
- [ ] 6.4 Run `nix flake check --no-build --no-update-lock-file` and verify all
  outputs evaluate
- [ ] 6.5 Execute both dedicated MicroVM checks and report their results
