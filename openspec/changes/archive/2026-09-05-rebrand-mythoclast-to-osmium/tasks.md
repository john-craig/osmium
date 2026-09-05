## 1. Inventory And Naming Contract

- [x] 1.1 Inventory active, compatibility, generated, and historical
  `mythoclast` occurrences and create the documented allowlist; verify the audit
  distinguishes permitted history from unexplained active names
- [x] 1.2 Define the Osmium naming map for project branding, Nix options,
  systemd units, commands, schema IDs, persistence paths, markers, flake
  outputs, and artifacts; verify every public old name has a migration or
  removal rule

## 2. Runtime Namespace Migration

- [x] 2.1 Rename active NixOS module namespaces and service/unit prefixes to
  Osmium; verify fresh configuration evaluation exposes canonical names and
  does not create duplicate old/new services
- [x] 2.2 Rename CLI wrappers, Python package/tool identities, schema IDs, and
  generated artifacts; verify new output uses Osmium and bounded old inputs are
  normalized or rejected with actionable guidance
- [x] 2.3 Implement idempotent migration of persisted paths, markers, snapshot
  metadata, and service state; verify state is preserved, migration is atomic,
  and secrets never enter logs or generated output
- [x] 2.4 Add compatibility aliases or explicit conflict assertions for legacy
  option/unit/command names; verify old and new declarations cannot create two
  authoritative runtime instances

## 3. Active Repository Rebrand

- [x] 3.1 Update README, examples, tests, flake descriptions/configuration
  names, and active OpenSpec references to Osmium; verify generated
  documentation and user-facing diagnostics contain no unexplained old names
- [x] 3.2 Preserve archived OpenSpec and Git history while documenting retained
  historical names; verify the naming audit allowlist is complete and stable

## 4. MicroVM Verification

- [x] 4.1 Add a fresh Osmium MicroVM test that boots the affected services and
  verifies primary behavior, canonical unit/command names, persistence, and
  generated artifact naming
- [x] 4.2 Add a migration MicroVM test that seeds Mythoclast-era persisted state,
  upgrades to Osmium, restarts/recreates the guest, and verifies state,
  lifecycle markers, credentials, and service behavior remain valid
- [x] 4.3 Add MicroVM coverage for old/new namespace conflicts and compatibility
  aliases, verifying no duplicate service or state authority is created
- [x] 4.4 Execute the fresh and migration MicroVM checks with `nix build
  .#checks.x86_64-linux.osmium-rebrand-fresh --print-build-logs` and `nix build
  .#checks.x86_64-linux.osmium-rebrand-migration --print-build-logs`; report
  both results

## 5. Final Verification

- [x] 5.1 Run `nix fmt` and verify no formatting changes remain
- [x] 5.2 Run `openspec validate rebrand-mythoclast-to-osmium --strict` and
  verify the change passes strict validation
- [x] 5.3 Run `nix flake check --no-build --no-update-lock-file` and verify all
  outputs evaluate
- [x] 5.4 Run the active-source naming audit and verify only documented
  compatibility or historical `mythoclast` occurrences remain
