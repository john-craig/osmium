# Naming Inventory

The canonical active identity is `osmium`. The audit command below searches
tracked source and documentation while excluding archived OpenSpec history and
this inventory:

```sh
git grep -n -i mythoclast -- ':!openspec/changes/archive/**' ':!NAMING-INVENTORY.md'
```

Every result from that audit must be covered by one of the entries below.

## Naming Map

| Former active name | Canonical Osmium name | Rule |
| --- | --- | --- |
| `services.mythoclast.*` and `mythoclast.host` | `services.osmium.*` and `osmium.host` | Legacy option paths are aliases to the canonical namespace; conflicting old/new declarations fail evaluation. |
| `mythoclast-*` systemd users, groups, units, and commands | `osmium-*` | New runtime units and executables use Osmium; bounded legacy command and unit aliases resolve to the canonical implementation. |
| `.mythoclast*` active defaults and markers | `.osmium*` | New deployments write Osmium defaults; the first boot migration copies known persisted state atomically and leaves a completion marker. |
| `mythoclast.filesystem.*` schema IDs | `osmium.filesystem.*` | New generated documents use Osmium; known persisted snapshot metadata is normalized atomically during migration. |
| `mythoclast-*` test, flake, and generated artifact names | `osmium-*` | Active user-facing and generated names use Osmium. |

## Intentional Active References

- `AGENTS.md`: project-level reverse-configuration guidance retains the former
  declaration name as historical compatibility terminology.
- `openspec/changes/rebrand-mythoclast-to-osmium/proposal.md`: describes the
  source and destination names and the intentionally deferred migration and
  compatibility work.
- `openspec/changes/rebrand-mythoclast-to-osmium/design.md`: records migration,
  compatibility, and historical provenance decisions for the former name.
- `openspec/changes/rebrand-mythoclast-to-osmium/specs/osmium-project-identity/spec.md`:
  specifies the former public interfaces and required future migration behavior.
- `openspec/changes/rebrand-mythoclast-to-osmium/tasks.md`: identifies deferred
  migration, compatibility, and MicroVM tasks using the former names.
- `openspec/changes/gitea-declarative-repositories/**`: untouched active change;
  its declarations and tests currently refer to the existing project identity.
- `openspec/changes/remote-gitea-capture-to-declarative-config/**`: untouched
  active change; its conversion contract currently refers to the existing
  project identity.

## Archived References

All occurrences under `openspec/changes/archive/**` are preserved as historical
OpenSpec provenance and are intentionally excluded from the active audit. Git
history is likewise not rewritten.

## Scope Boundary

The active implementation uses Osmium names. The compatibility module provides
bounded old option, command, and unit aliases and migrates known persisted
state; archived OpenSpec changes and Git history remain unchanged.
