## Why

The project is being renamed from Mythoclast to Osmium, but the current name is
embedded across user-facing documentation, NixOS option namespaces, service
units, command names, schema identifiers, persistence markers, examples, and
tests. A coordinated rebrand is needed to establish one canonical identity
without losing persisted service state or leaving ambiguous mixed naming in new
deployments.

## What Changes

- **BREAKING** Rename the canonical project and user-facing brand from
  `mythoclast` to `osmium`.
- **BREAKING** Rename public NixOS option namespaces, systemd unit prefixes,
  executable names, schema identifiers, persistence markers, and generated
  artifact names to their `osmium` equivalents.
- Update flake descriptions, configuration names where appropriate, examples,
  README content, test names, and source documentation to use Osmium.
- Define migration behavior for existing persisted state, including old
  state-directory names, snapshot metadata, completion markers, and service
  records.
- Provide a deliberate compatibility or migration path for existing
  `services.mythoclast` configurations rather than silently interpreting both
  namespaces as independent services.
- Preserve archived OpenSpec history and historical commit content as provenance;
  new active specifications and implementation documentation use Osmium.
- Add validation that newly generated names do not accidentally retain the old
  canonical namespace outside documented compatibility and historical paths.

## Capabilities

### New Capabilities

- `osmium-project-identity`: Canonical project branding, runtime namespace
  migration, compatibility boundaries, and repository-wide naming guarantees.

### Modified Capabilities

- None.

## Impact

- Affects NixOS module option paths, systemd service/timer names, CLI commands,
  Python/Nix schema identifiers, persistence locations, generated artifacts,
  flake outputs, tests, examples, and documentation.
- May require migration code or activation steps for existing deployments and
  explicit handling of old state paths.
- Existing configurations and scripts using `mythoclast` may require updates;
  the design must define the supported compatibility window and failure mode.
- No service behavior should change beyond naming, migration, and compatibility
  semantics.
