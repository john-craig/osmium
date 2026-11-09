## Why

Traefik is already fully configurable through the NixOS service and current nixpkgs package, but it is not yet represented as an Osmium service. Moving that existing configuration surface into a dedicated Osmium MicroVM gives the reverse proxy the same persistence, lifecycle, networking, and verification guarantees as the other Osmium services without inventing a second Traefik configuration language.

## What Changes

- Add an Osmium Traefik service module backed by the existing `services.traefik` NixOS module and nixpkgs package.
- Preserve the upstream static and dynamic configuration surfaces, including options, files, environment files, entrypoints, providers, routers, services, middlewares, TLS, ACME, and dashboard settings.
- Add dedicated Traefik service-account ownership, persistent `dataDir` handling, MicroVM port forwarding, firewall assertions, readiness checks, and clean shutdown/restart behavior.
- Ensure configuration files and runtime environment files are generated or referenced without embedding secret values in the Nix store or process arguments.
- Define safe dashboard and API exposure boundaries; Traefik is a routing/control-plane service, not an application requiring a Keycloak login gateway.
- Add review-only drift detection and live capture for representable Traefik runtime/static/dynamic configuration, explicitly marking provider-generated or unsupported state incomplete.
- Add booting MicroVM checks for lifecycle, persistence, configured routing, TLS/ACME secret handling, dashboard/API boundaries, drift conversion, and live capture.

## Capabilities

### New Capabilities
- `traefik-service`: Runs the existing configurable Traefik NixOS service as a persistent Osmium MicroVM service with explicit network and secret boundaries.
- `traefik-reverse-configuration`: Observes and converts representable Traefik configuration and runtime routing state into safe, review-only candidates.

### Modified Capabilities
- None.

## Impact

- Adds `modules/services/traefik.nix`, module imports, documentation, MicroVM test files, and flake checks.
- Reuses `pkgs.traefik` and upstream `services.traefik` options instead of adding a second proxy configuration model.
- Adds persistent state for ACME certificates and other Traefik-owned data under the Osmium persistence boundary.
- Existing services may later use Traefik as their ingress, but this change does not automatically rewire existing service endpoints or configure application-specific routes.
- No Keycloak or FreeIPA integration is added. Traefik's control plane has no user-facing application authentication flow; dashboard/API access is bounded by explicit listener and network configuration instead.
