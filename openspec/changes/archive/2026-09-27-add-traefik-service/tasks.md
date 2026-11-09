## 1. Service Foundation

- [x] 1.1 Add `modules/services/traefik.nix` and import it from `modules/default.nix`, using `pkgs.traefik` and the upstream `services.traefik` module; verify the disabled module does not alter existing configurations and enabled evaluation succeeds.
- [x] 1.2 Define Osmium-specific options for state/data directory, guest listeners, host forwarding, firewall policy, readiness endpoint, dashboard/API exposure, and upstream static/dynamic configuration passthrough; verify invalid paths, listener collisions, unsupported exposure combinations, and unsafe runtime references fail evaluation.
- [x] 1.3 Configure the dedicated Traefik account, persistent `dataDir`, restrictive ACME/state ownership, readiness ordering, graceful restart, and impermanent MicroVM persistence; verify retained ACME/state fixtures survive guest-root recreation.
- [x] 1.4 Preserve static/dynamic configuration files/options, environment files, providers, entrypoints, routers, services, middlewares, TLS, and ACME settings through the native module; verify a representative configuration reaches the running process without secret values in Nix store paths, unit arguments, or diagnostics.
- [x] 1.5 Implement explicit MicroVM forwards and firewall rules for declared entrypoints and safe dashboard/API defaults; verify undeclared guest/host ports are unavailable and declared entrypoints are reachable.
- [x] 1.6 Add the `traefik` flake check and execute `nix build .#checks.x86_64-linux.traefik --print-build-logs`; verify a booting MicroVM exercises readiness, routing, forwarding, persistence, runtime-secret exclusion, and dashboard/API boundaries.

## 2. Reverse Configuration

- [x] 2.1 Implement `osmium-traefik-observe` for deterministic observation of static/dynamic source references, effective local API objects, entrypoints, routers, services, middlewares, TLS metadata, provider provenance, ownership, and completeness without mutating Traefik or source files.
- [x] 2.2 Implement review-only drift comparison and candidate conversion for Osmium-managed configuration, excluding ACME/TLS/provider secrets and preserving unresolved file/secret references; verify candidate output is deterministic, secret-safe, provenance-bearing, and incomplete when replay prerequisites are unavailable.
- [x] 2.3 Implement live capture from runtime observation, including source/provider distinction and explicit handling of provider-generated objects, generated certificates, missing file paths, and unsupported fields; verify capture never uses an independently authored fixture as its source.
- [x] 2.4 Add `traefik-drift-reverse-configuration` and execute `nix build .#checks.x86_64-linux.traefik-drift-reverse-configuration --print-build-logs`; verify a booting MicroVM changes a supported route, derives a candidate from live observation, proves source non-mutation, and validates replay or exact incompleteness.
- [x] 2.5 Add `traefik-live-capture-reverse-configuration` and execute `nix build .#checks.x86_64-linux.traefik-live-capture-reverse-configuration --print-build-logs`; verify a booting MicroVM creates runtime file-provider state, captures it with provenance, excludes secrets, proves source non-mutation, and validates replay or exact blockers.

## 3. Documentation And Verification

- [x] 3.1 Add `docs/traefik.md` covering native option passthrough, package provenance, state persistence, entrypoint forwarding, configuration-file ownership, runtime secret files, dashboard/API exposure, SSO boundary, migration, rollback, and reverse-configuration limitations; verify documented options and commands match the module and flake outputs.
- [x] 3.2 Add the Traefik guest/test configurations and all three MicroVM checks to `flake.nix`; verify `nix flake check --no-build --no-update-lock-file` evaluates the module and checks.
- [x] 3.3 Run `openspec validate add-traefik-service --strict` and `git diff --check`; verify all artifacts are structurally valid and whitespace-clean.
- [x] 3.4 Execute and report `nix build .#checks.x86_64-linux.traefik --print-build-logs`, `nix build .#checks.x86_64-linux.traefik-drift-reverse-configuration --print-build-logs`, and `nix build .#checks.x86_64-linux.traefik-live-capture-reverse-configuration --print-build-logs`; verify each named check boots a MicroVM and exercises the service or runtime-derived reverse configuration.
