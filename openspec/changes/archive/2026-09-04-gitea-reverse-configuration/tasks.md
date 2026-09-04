## 1. Export Contract

- [x] 1.1 Define the sanitized export schema and forbidden-field policy and verify credentials never enter the renderer input
- [x] 1.2 Define deterministic identity-derived declaration keys and collision handling and verify output is independent of API order
- [x] 1.3 Define candidate, unresolved-secret, and exclusion reason formats and verify unsafe records are represented explicitly

## 2. Configuration Rendering

- [x] 2.1 Render selected users and organizations as deterministic Nix-shaped candidates and verify supported fields and owner references
- [x] 2.2 Render unresolved password-file requirements without secret contents and verify incomplete candidates cannot be activated accidentally
- [x] 2.3 Add human-readable and machine-readable export modes and verify both preserve the same safety exclusions

## 3. Review And Safety Boundaries

- [x] 3.1 Keep export limited to stdout or an explicit output path and verify it does not alter Gitea, Nix source, adoption state, or version-control state
- [x] 3.2 Refuse or exclude administrators, ambiguous owners, unsafe names, duplicate matches, and external identity-provider records and verify reason codes
- [x] 3.3 Keep adoption separate from export and document the manual secret completion, evaluation, review, and activation workflow

## 4. MicroVM And Verification

- [x] 4.1 Extend the Gitea MicroVM test with unmanaged users and organizations and verify candidate generation and owner mapping
- [x] 4.2 Verify repeated export is deterministic, excludes credentials, and leaves identifiers, ownership, metadata, and database state unchanged
- [x] 4.3 Verify administrator and ownership-conflict exclusions and explicit adoption refusal behavior
- [x] 4.4 Run `nix fmt`, `openspec validate gitea-reverse-configuration --strict`, `nix flake check --no-build --no-update-lock-file`, and `nix build .#checks.x86_64-linux.gitea --print-build-logs`
