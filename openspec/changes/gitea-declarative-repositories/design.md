## Context

The Gitea module currently provisions users and organizations through an
idempotent runtime reconciliation path and has review-only drift/export tooling
for those identities. Repository declarations need to use the same lifecycle
and runtime credential model while adding two reverse-configuration paths
required by `AGENTS.md`: conversion from declared-vs-observed drift and capture
from a live Gitea instance.

The first version targets repository metadata, not repository contents. Gitea
repository identity is the pair `(owner login, repository name)`; repository
IDs are observed provenance and must not become declarative identity keys.

## Goals / Non-Goals

**Goals:**

- Declaratively ensure user-owned and organization-owned repositories exist with
  supported metadata.
- Preserve content, history, and stable owner/name identity during reconciliation.
- Produce deterministic, secret-free candidates from both drift and live capture.
- Make incomplete or ambiguous reverse configuration impossible to mistake for
  a complete declaration.
- Exercise both reverse-configuration directions against running Gitea in
  separate MicroVM checks.

**Non-Goals:**

- Deleting repositories when declarations disappear.
- Transferring ownership, forking, mirroring, or recreating repository content.
- Managing commits, branches, releases, LFS, deploy keys, collaborators,
  webhooks, access tokens, or repository secrets.
- Supporting every Gitea API field in the first implementation.

## Decisions

### Use stable owner/name declarations

The Nix option will be an attribute set keyed by a stable local declaration key,
with `owner` and `name` as authoritative Gitea identity fields. `owner` will be
typed as either a user or organization reference rather than an arbitrary API
ID. Duplicate owner/name pairs fail evaluation. Local keys are only for Nix
organization and generated output; they do not determine Gitea identity.

This avoids API-ID coupling and makes declarations portable across recreated
instances. A flat repository list or repository-ID-only model was rejected
because neither expresses ownership safely.

### Restrict reconciliation to metadata updates

The runtime reconciler will create a repository only after its owner is
available, then update a fixed allowlist of metadata: description, private
visibility, default branch, website, issues, wiki, and pull-request feature
flags where the installed Gitea API supports them. It will never write Git
objects or alter content. Existing records with matching owner/name are updated
in place; owner changes are rejected rather than implemented as transfers.

The module will use the existing runtime administrator credential path and will
not put credential contents in evaluated configuration, state markers, or
logs. Reconciliation remains non-destructive when a declaration is removed.

### Normalize one repository observation model for both reverse paths

The drift detector and live capture command will normalize API records into the
same repository observation schema. Each record includes owner kind/login,
repository name, supported metadata, observed API provenance, and a list of
unsupported fields. Drift compares this model with declared values; live
capture produces it directly. The converter consumes normalized observations,
not raw API responses, so output ordering and API response shape cannot vary
the generated Nix candidate.

### Treat repository content and sensitive features as findings

The converter will emit metadata declarations only. Repositories requiring
content/history, or containing secrets in hooks, webhooks, deploy keys, or
similar integrations, will remain represented by findings without sensitive
values. A capture can still be useful for review, but completeness is false
whenever required metadata or owner mapping is missing. This makes the boundary
explicit instead of silently suggesting that metadata reproduces repository
state.

### Keep reverse configuration review-only

Drift conversion and live capture will write JSON/Nix-shaped output only to
stdout or selected local paths. They will not mark repositories managed, alter
Gitea, edit Nix source, or activate a declaration. A separate evaluation and
normal reconciliation path will consume reviewed output.

### Use separate MicroVM checks for the two directions

The drift check will boot Gitea with a declared repository, mutate supported
metadata through the API, run drift detection, convert the runtime observation,
and apply the reviewed candidate in a separate configuration path. The live
capture check will create user- and organization-owned repositories externally,
capture the running service, convert the generated artifact, and consume that
artifact for a separate Mythoclast evaluation/reconciliation. Both checks will
assert source state and secrets remain protected, and neither will use a
hand-authored equivalent repository observation as conversion input.

## Risks / Trade-offs

- [Risk] Gitea versions expose different repository fields → use API capability
  detection, a fixed supported-field map, and explicit unsupported findings.
- [Risk] Repository contents are mistaken for declarative metadata → document
  the boundary in generated output and fail completeness when content
  reproduction is required.
- [Risk] Owner ambiguity can create a repository under the wrong account →
  require exactly one resolved user or organization and reject transfers.
- [Risk] Updating private/feature settings can affect users → make changes
  explicit in the declaration and verify them through the running API in
  integration tests.
- [Risk] Runtime API credentials leak through scripts → read them only at
  runtime from the existing secret-file path and redact errors and diagnostics.
- [Risk] Drift and live capture observe different moments → include observation
  timestamps/generation metadata and mark required failed or inconsistent probes
  incomplete.

## Migration Plan

1. Add repository option types and assertions without enabling any repository
   declarations by default.
2. Deploy declarations to an existing instance; matching repositories are
   reconciled in place, while missing repositories are created only for valid
   owners.
3. Run the drift or live-capture reverse-configuration command to produce a
   candidate, review findings and metadata, and supply any required secret or
   content decisions manually.
4. Evaluate and activate the reviewed declaration through the normal NixOS
   workflow.
5. Roll back by removing repository declarations and reverting the module
   configuration. Existing repositories remain intact by design.
