## Why

Drift reports can identify Gitea records that are not represented in Nix, but
operators still need a safe way to turn an observed record into a reviewable
configuration candidate. Reverse generation must preserve the distinction
between observed state and approved desired state and must not invent secrets or
silently adopt accounts.

## What Changes

- Add a reviewed export workflow that renders sanitized observed users and organizations as Nix-shaped configuration.
- Define deterministic declaration keys and preserve Gitea stable identities in generated fields.
- Omit passwords, password hashes, tokens, keys, and secret paths from generated output.
- Mark unresolved secret requirements and ambiguous ownership instead of guessing.
- Add explicit safeguards for administrators, ownership conflicts, duplicate matches, unsafe names, and external identity sources.
- Keep export read-only and separate from adoption, activation, repository edits, and commits.
- Add MicroVM and output tests proving deterministic, secret-free, non-mutating export behavior.

## Capabilities

### New Capabilities

- `gitea-reverse-configuration`: Reviewed generation of declarative configuration candidates from observed Gitea state.

### Modified Capabilities

- None.

## Impact

- Adds an export command/helper consuming the normalized state produced by drift detection.
- Extends Gitea module or tooling options for explicit export invocation and output format.
- Extends `tests/gitea.nix` and likely adds fixture tests for deterministic rendering and safety refusals.
- Updates README and operational documentation with the manual secret-completion and review workflow.
- Does not automatically adopt records, modify Nix source, activate generated configuration, or commit changes.
