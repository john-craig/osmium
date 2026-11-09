## 1. Service Module

- [ ] 1.1 Add the Grocy service module and import it from `modules/default.nix`; verify NixOS option evaluation succeeds with Grocy disabled and enabled
- [ ] 1.2 Configure the packaged Grocy application, PHP/web runtime, persistent data directory, service user, and explicit listener boundary; verify the generated system contains the expected service units and paths
- [ ] 1.3 Add a booting Grocy MicroVM fixture and flake check; verify the health endpoint and primary web/API behavior from inside the test
- [ ] 1.4 Verify persistent state across MicroVM replacement or restart by creating a supported record and checking it after the second boot

## 2. Declarative Identities

- [ ] 2.1 Define declaration options for users, runtime password secret paths, permissions, and optional one-token-per-user bootstrap; verify secrets do not appear in evaluated configuration or the Nix store
- [ ] 2.2 Implement the ownership ledger and fail-closed matching for users; verify create-once, update-owned, preserve-unmanaged, and ambiguous-match behavior in a running MicroVM
- [ ] 2.3 Implement runtime password bootstrap and permission reconciliation; verify protected secret consumption and administrator/non-administrator access behavior in the identity integration test
- [ ] 2.4 Implement API-token bootstrap, persistence, protected output, and changed-secret rotation; verify unchanged activations do not duplicate tokens and changed secret files rotate exactly the owned token
- [ ] 2.5 Add identity drift and live-capture conversion; verify passwords and token values are omitted, provenance is present, and incomplete results are explicit

## 3. Declarative Reference Data

- [ ] 3.1 Define declaration options for locations, quantity units, quantity-unit conversions, product groups, and shopping locations; verify dependency ordering and option validation
- [ ] 3.2 Implement API discovery, natural-key matching, ownership recording, create/update behavior, and ambiguity handling for reference entities; verify reconciliation against a running Grocy instance
- [ ] 3.3 Preserve unmanaged reference records and exclude products, barcodes, recipes, recipe positions, chore/task definitions, stock, shopping-list contents, and operational history; verify activation does not replay transactional events
- [ ] 3.4 Add reference-data drift conversion and live capture from runtime API observations; verify changed runtime attributes appear in generated declarations and unsupported relationships are marked incomplete

## 4. Reverse Configuration Integration

- [ ] 4.1 Add the Grocy drift reverse-configuration MicroVM check and expose it as a flake check such as `nix build .#checks.x86_64-linux.grocy-drift-reverse-configuration --print-build-logs`; verify the generated declaration comes from observed runtime drift and source Grocy is unchanged
- [ ] 4.2 Add the Grocy live-capture reverse-configuration MicroVM check and expose it as a flake check such as `nix build .#checks.x86_64-linux.grocy-live-capture-reverse-configuration --print-build-logs`; verify runtime-created reference data is captured and the resulting declaration behavior is reproducible
- [ ] 4.3 Run `openspec validate add-grocy-service --strict`, `git diff --check`, and all Grocy MicroVM checks; record the commands and results in the implementation report
