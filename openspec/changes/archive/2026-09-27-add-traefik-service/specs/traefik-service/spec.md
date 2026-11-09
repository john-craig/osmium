## Purpose

Provides the existing fully configurable NixOS Traefik service as a persistent, network-bounded Osmium MicroVM service without introducing a competing proxy configuration model.

## ADDED Requirements

### Requirement: Traefik uses the upstream NixOS configuration surface
The system SHALL expose an Osmium Traefik service that delegates static and dynamic configuration to the upstream NixOS Traefik module, including configuration files/options, environment files, providers, entrypoints, routers, services, middlewares, TLS, ACME, and dashboard/API settings supported by the pinned nixpkgs version. Osmium SHALL not silently discard supported upstream configuration.

#### Scenario: Existing Traefik configuration is preserved
- **WHEN** an operator supplies valid upstream static and dynamic Traefik configuration through the Osmium service
- **THEN** the running Traefik process receives the equivalent configuration and serves the declared entrypoints and routes

#### Scenario: Unsupported configuration is surfaced
- **WHEN** a configuration attribute is not supported by the pinned upstream NixOS module or package
- **THEN** evaluation or startup fails with a diagnostic rather than silently ignoring that attribute

### Requirement: Traefik runs with persistent service state
The system SHALL run Traefik under a dedicated service account, persist its declared `dataDir` under the Osmium persistence boundary, preserve ACME state across guest-root recreation, and perform readiness-ordered startup and graceful restart. Runtime secrets such as ACME DNS credentials, TLS private keys, and provider credentials SHALL be supplied through runtime-only environment files or paths and SHALL not be embedded in the Nix store.

#### Scenario: ACME state survives recreation
- **WHEN** Traefik has obtained persistent ACME state and the impermanent MicroVM root is recreated with `/persistent` retained
- **THEN** Traefik starts with the retained ACME state and does not unnecessarily discard or recreate certificates

#### Scenario: Runtime provider secret stays out of the store
- **WHEN** a provider or ACME resolver uses a declared runtime environment file
- **THEN** the service consumes it at runtime and the secret is absent from Nix store paths, generated configuration reports, and process arguments

### Requirement: Traefik network exposure is explicit and bounded
The system SHALL require explicit guest listeners and MicroVM host forwarding for every exposed Traefik entrypoint, SHALL reject duplicate or conflicting host/guest ports, and SHALL allow firewall ports only for declared listeners. The Traefik API and dashboard SHALL be loopback-only or explicitly exposed through a declared protected entrypoint; enabling a dashboard SHALL not implicitly expose the unauthenticated API to the guest or host network.

#### Scenario: Declared entrypoint is reachable
- **WHEN** a declared HTTP or HTTPS entrypoint and host forward are configured
- **THEN** the booting MicroVM exposes exactly that listener and a request reaches the configured route

#### Scenario: Dashboard is not implicitly exposed
- **WHEN** the Traefik dashboard/API is enabled without an explicit exposed listener policy
- **THEN** it remains unavailable from the guest network except through its declared safe bind boundary

### Requirement: Traefik has an explicit control-plane authentication boundary
Traefik SHALL be treated as a routing and control-plane service rather than a browser-facing application. Osmium SHALL not place Traefik behind a generic Keycloak/FreeIPA login gateway or synthesize identity headers. If dashboard/API protection is needed, the declaration SHALL use Traefik-native authentication middleware or an explicitly declared upstream boundary, and machine/API access SHALL remain separately testable.

#### Scenario: Machine routing is not confused with browser SSO
- **WHEN** an operator enables Traefik routes and a dashboard/API listener
- **THEN** the service exposes the declared machine routing behavior without claiming that Keycloak or FreeIPA authenticates Traefik itself

### Requirement: Service behavior is exercised in a MicroVM
The system SHALL expose a `traefik` flake check that boots the Traefik MicroVM and verifies readiness, configured routing, entrypoint forwarding, persistence, runtime secret exclusion, and dashboard/API exposure boundaries.

#### Scenario: Traefik lifecycle check executes
- **WHEN** `nix build .#checks.x86_64-linux.traefik --print-build-logs` runs
- **THEN** it boots a MicroVM and exercises the running Traefik service rather than only evaluating NixOS options
