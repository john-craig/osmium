## Context

See `proposal.md` for motivation. nixpkgs already provides `pkgs.traefik` and the native `services.traefik` module, including static/dynamic option and file configuration. Osmium currently has application-specific Nginx and oauth2-proxy compositions, but no general reverse-proxy service. The service must therefore preserve Traefik's existing configuration contract while adding Osmium's MicroVM, persistence, and verification boundaries.

Traefik is a reverse proxy and routing/control plane, not an end-user application. Keycloak/FreeIPA browser SSO is not appropriate for the Traefik process itself. If an operator wants dashboard/API protection, Traefik-native middleware or a separately declared protected route remains the operator's responsibility.

## Goals / Non-Goals

**Goals:**

- Wrap the upstream NixOS Traefik module with the smallest possible Osmium-specific interface.
- Preserve upstream package, static/dynamic options, file paths, environment files, providers, and runtime behavior.
- Make persistence, listener forwarding, dashboard/API exposure, and runtime secrets explicit and testable.
- Add runtime-derived reverse configuration without pretending provider-generated state is fully reproducible.

**Non-Goals:**

- Add a new router/service/middleware DSL on top of Traefik.
- Automatically configure routes for existing Osmium services.
- Add Keycloak, FreeIPA, oauth2-proxy, identity headers, or a generic authentication gateway for Traefik.
- Replace Traefik's own provider model, ACME implementation, or dynamic configuration semantics.

## Decisions

### Delegate configuration to `services.traefik`

`services.osmium.traefik` will expose the native Traefik options through a deliberate passthrough or compatible option surface and set only Osmium-specific defaults: service ownership, state directory, guest/host ports, persistence, and safe exposure assertions. Static and dynamic configuration files take precedence exactly as upstream defines. This prevents divergence from nixpkgs and means operators can continue to use the complete Traefik feature set.

Alternatives considered:

- A custom Osmium router DSL: rejected because Traefik is already fully configurable and a second model would lose features and create conversion ambiguity.
- Copying the entire nixpkgs module: rejected because it would fork upstream behavior and make updates fragile.
- Running Traefik from Docker: rejected because a native nixpkgs package and module already exist.

### Persist only Traefik-owned state

The module will set `services.traefik.dataDir` below the configured `/var/lib` service state and persist it with the Traefik account. This primarily protects ACME storage and other Traefik-created state. Operator-authored static/dynamic configuration files and environment files remain external configuration inputs; the module will not copy their secret contents into persistent reports or generated Nix artifacts.

### Make network exposure explicit

The module will provide typed guest/host forwarding declarations for configured entrypoints or a documented default HTTP/HTTPS pair. Evaluation will detect collisions between host forwards, guest listeners, and reserved control-plane listeners. The API/dashboard will be disabled by default or bound to loopback unless the operator explicitly declares a protected exposure policy. No implicit `api.insecure` exposure will be added.

### Keep secret references opaque

Runtime environment files remain paths in Nix configuration, while their values are consumed by systemd/Traefik at runtime. ACME DNS credentials, TLS keys, and provider secrets will be represented in observations only by path/reference metadata and redaction findings. Diagnostics must avoid command-line expansion and secret-bearing environment dumps.

### Use Traefik's local API and source files for reverse configuration

The observation tool will collect the effective static configuration where safely available, declared dynamic file content, and local Traefik API objects when the API is explicitly enabled on a loopback/control endpoint. It will normalize routers, services, middlewares, entrypoints, TLS metadata, and provider names. It will never scrape the dashboard UI or write configuration back. Provider-generated objects, generated certificates, secret-bearing values, and options without a stable source are marked unresolved.

Alternatives considered:

- Read Traefik's internal ACME/config databases: rejected as implementation-specific and secret-sensitive.
- Capture only authored files: insufficient for runtime drift and misses effective provider state.
- Treat `/api` output as complete configuration: rejected because it omits source provenance and generated/provider prerequisites.

### SSO assessment

Traefik has no browser-facing application login surface in this service boundary; it routes requests and optionally exposes an administrative dashboard/API. The service therefore uses the protocol/surface exemption from the Keycloak gateway pattern. The design preserves machine routing and explicit dashboard protection through Traefik-native configuration, and the boundary test verifies that no implicit SSO or identity-header bypass is generated.

## Risks / Trade-offs

- [Native option passthrough can change with nixpkgs] → Pin the tested nixpkgs input, evaluate representative static/dynamic configurations, and fail tests when the expected upstream option surface changes.
- [Provider state cannot always be replayed from Traefik API output] → Include provider/source provenance and explicit incomplete findings in candidates.
- [ACME state contains sensitive material and certificate renewal is time-dependent] → Persist the data directory with restrictive ownership, never export its contents, and test persistence with a controlled file-provider/certificate fixture rather than relying on live ACME issuance.
- [Dashboard/API exposure is easy to misconfigure] → Keep insecure API disabled by default, require explicit exposure, and test both loopback denial and declared protected access.
- [Moving an existing deployment can change paths and network boundaries] → Document a cutover that preserves existing configuration files/dataDir, validates the MicroVM before DNS changes, and does not automatically rewrite external routes.

## Migration Plan

1. Add the module disabled by default and validate the existing Traefik static/dynamic configuration against the native NixOS module.
2. Copy or mount existing operator-owned configuration files and environment files into the new MicroVM without embedding their contents into the Nix store.
3. Set `dataDir` to the persistent Osmium path and copy existing ACME state with Traefik ownership and restrictive permissions.
4. Boot the MicroVM, verify entrypoints, routes, certificate loading, and dashboard/API boundaries, then change DNS or host forwarding to the new listener.
5. Roll back by stopping the MicroVM and restoring the previous Traefik process/configuration. The module does not delete old configuration, ACME state, or external provider resources.
