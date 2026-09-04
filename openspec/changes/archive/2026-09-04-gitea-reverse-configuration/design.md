## Context

This change follows `gitea-drift-detection`, which supplies a normalized
observed-state snapshot. The current Gitea declarations use local attrset keys
separate from Gitea usernames, while runtime password files are intentionally
kept out of evaluated configuration and persistent metadata.

## Goals / Non-Goals

**Goals:**

- Produce a deterministic candidate suitable for human review and manual merge.
- Make missing secrets and unsafe records visible rather than silently guessing.
- Preserve the distinction between observation, export, adoption, and activation.
- Reuse the drift snapshot and its field allowlist.

**Non-Goals:**

- Full bidirectional synchronization or automatic Git commits.
- Recovering secrets, secret-manager paths, historical declaration keys, or intent.
- Automatic adoption, Gitea mutation, configuration activation, or ownership transfer.
- Exporting repositories, teams, hooks, tokens, SSH keys, or all Gitea settings.

## Decisions

### Use a normalized snapshot as the input boundary

The renderer will accept sanitized normalized state rather than scrape API
responses itself. This gives drift detection and export one field contract and
prevents a renderer from accidentally gaining access to unfiltered credentials.

### Generate Nix-shaped output, not source edits

The first interface will emit a complete candidate fragment to stdout or an
explicit path. It will not patch a user's Nix files because source layout,
secret naming, module composition, and formatting are project-specific. A later
editor integration can consume the same structured output.

### Use stable identity-derived declaration keys

Generated keys will be sanitized deterministic forms of the Gitea identity, with
a collision check. Collisions will be reported and excluded rather than
resolved by an ordering-dependent suffix. The explicit `username` or `name`
field remains the service identity.

### Represent unresolved credentials explicitly

Generated users will contain a clearly unresolved password-file requirement or a
commented placeholder according to the selected output mode. The renderer will
never map a live password to a guessed SOPS key or filesystem path. The result
must require a human to connect it to a secret before activation.

### Make safety exclusions first-class output

The structured output will contain both candidates and exclusions with reason
codes. This is preferable to silently dropping records and allows operators to
review why administrator accounts, ambiguous owners, and external identities
were not rendered.

### Keep adoption as a later explicit boundary

The export command will not create management markers or alter desired state.
If adoption is later added, it will be a separate command with an explicit
allowlist and a second safety validation pass.

## Risks / Trade-offs

- [Risk] Generated declarations may overwrite an existing local key. -> Mitigation: detect key collisions and require manual key selection.
- [Risk] Operators may activate output without supplying a secret. -> Mitigation: use an unresolved required value and test that incomplete output cannot evaluate as a usable identity declaration.
- [Risk] An observed organization owner may be hidden or changed during export. -> Mitigation: exclude ambiguous ownership and require a fresh complete snapshot.
- [Risk] Nix formatting or repository layout may differ from the generated fragment. -> Mitigation: define the output as a candidate fragment and leave source integration to review tooling.
- [Risk] Future fields could accidentally expose sensitive data. -> Mitigation: render only the shared normalized allowlist and add regression tests that scan every output format for forbidden keys.

## Migration Plan

Deploy after drift detection is available. Operators run export against a
read-only snapshot, review exclusions, add secret-file references manually,
evaluate the resulting configuration, and activate it through the normal NixOS
workflow. No existing Gitea records or declarations are changed by enabling the
export capability.
