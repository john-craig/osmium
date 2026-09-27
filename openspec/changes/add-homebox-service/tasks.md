## 1. Service Module

- [ ] 1.1 Add the Homebox service module and import it from `modules/default.nix`; verify NixOS option evaluation succeeds with Homebox disabled and enabled
- [ ] 1.2 Configure the packaged Homebox binary, database/storage paths, service user, listener, reverse-proxy trust, and WebSocket boundary; verify generated units and paths
- [ ] 1.3 Configure native OIDC with runtime-only client secrets and redirect settings; verify secrets are absent from evaluated configuration and the Nix store
- [ ] 1.4 Add a booting Homebox MicroVM check; verify status, browser/API access, OIDC redirect behavior, and WebSocket operation
- [ ] 1.5 Verify database and storage persistence across MicroVM replacement or restart by creating a collection and supported metadata record

## 2. Runtime Identity Bootstrap

- [ ] 2.1 Define identity declarations for users, groups, memberships, runtime password inputs, bootstrap credentials, and API-key output/rotation inputs; verify secret values never enter the Nix store or logs
- [ ] 2.2 Implement Homebox application/schema/migration version detection and supported-version gating; verify unsupported or migrating databases fail closed without mutation
- [ ] 2.3 Implement the runtime database helper for user and group creation/update and membership reconciliation; verify UUID ownership, create-once behavior, role handling, unmanaged preservation, and ambiguity failures in a MicroVM
- [ ] 2.4 Implement API-supported identity operations where available and coordinate helper execution with Homebox service writes; verify no concurrent-write corruption occurs
- [ ] 2.5 Implement API-key ownership, protected one-time output, reuse, and changed-rotation-secret replacement; verify unchanged activation does not duplicate keys and rotation revokes only the owned key
- [ ] 2.6 Add identity drift conversion and live capture; verify passwords, OIDC secrets, sessions, invitations, and raw API keys are omitted and incomplete results include provenance

## 3. Declarative Collection Metadata

- [ ] 3.1 Define declarations for tags, nested tag hierarchies, entity types, templates, and typed template fields; verify option validation rejects invalid references and hierarchy cycles
- [ ] 3.2 Implement REST API reconciliation with retained UUID ownership/adoption mappings; verify dependency ordering, owned updates, unmanaged preservation, and ambiguity failures in a running MicroVM
- [ ] 3.3 Exclude inventory entities, attachments, maintenance, import/export jobs, notifiers, duplicate actions, and bulk actions; verify repeated activation creates no event-like duplicates
- [ ] 3.4 Add metadata drift conversion and live capture; verify runtime changes appear in generated declarations with provenance and unsupported relationships are marked incomplete

## 4. Reverse Configuration Integration

- [ ] 4.1 Add the Homebox drift reverse-configuration MicroVM check and expose it as a flake check such as `nix build .#checks.x86_64-linux.homebox-drift-reverse-configuration --print-build-logs`; verify runtime drift is converted without mutating Homebox
- [ ] 4.2 Add the Homebox live-capture reverse-configuration MicroVM check and expose it as a flake check such as `nix build .#checks.x86_64-linux.homebox-live-capture-reverse-configuration --print-build-logs`; verify declarations come from runtime observation and reproduce supported behavior
- [ ] 4.3 Run `openspec validate add-homebox-service --strict`, `git diff --check`, and all Homebox MicroVM checks; record the command results and any supported-version limitations
