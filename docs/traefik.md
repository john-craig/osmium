# Traefik

Osmium provides `services.osmium.traefik` as a thin wrapper around the native
NixOS `services.traefik` module. The wrapper is disabled by default and uses
`pkgs.traefik` through the upstream package option.

## Configuration

The module preserves native Traefik configuration through:

- `staticConfigOptions` and `dynamicConfigOptions`
- `staticConfigFile` and `dynamicConfigFile`
- `environmentFiles`
- native providers, entrypoints, routers, services, middlewares, TLS, and ACME
  settings in those upstream options/files

Osmium adds explicit `entrypoints` declarations for guest ports and optional
MicroVM host forwards. Guest ports and host forwards must not collide. TCP and
UDP firewall rules are generated from those declarations.

The readiness endpoint is enabled by default on loopback port `8080`. Generated
readiness configuration requires `staticConfigFile = null`. The dashboard/API
is disabled by default. When enabled it is loopback-only unless
`dashboard.exposure = "entrypoint"` is selected. Entrypoint exposure requires a
named middleware and is never configured as insecure API exposure.

Example:

```nix
services.osmium.traefik = {
  enable = true;
  entrypoints.web = { guestPort = 8000; hostPort = 38080; };
  staticConfigOptions.entryPoints.web.address = ":8000";
  dynamicConfigOptions.http.routers.app = {
    rule = "Host(`app.example.test`)";
    entryPoints = [ "web" ];
    service = "app";
  };
};
```

## State And Secrets

`dataDir` defaults to `/var/lib/traefik`, is persisted through
`environment.persistence`, and is owned by the dedicated `traefik` account with
mode `0700`. This protects ACME and other Traefik-owned state. Operator-owned
configuration files remain external inputs and are not copied into generated
declarations.

Environment files are runtime paths and must not point into `/nix/store`.
Secret values are consumed by systemd/Traefik at runtime; they must not be
placed in static options, command arguments, diagnostics, or generated
reverse-configuration artifacts.

## SSO Boundary

Traefik is a routing/control-plane process rather than a browser-facing
application login surface. The module therefore does not add Keycloak, OAuth2
proxying, identity headers, or an implicit gateway. Protect a dashboard/API
entrypoint with a Traefik-native middleware or an explicitly declared upstream
authentication boundary. Machine routing remains unchanged.

## Migration And Rollback

1. Validate existing static/dynamic configuration against the native module.
2. Mount or copy operator-owned configuration and runtime environment files
   without embedding secret values in Nix.
3. Set `dataDir` to the persistent path and preserve ACME ownership/mode.
4. Boot and verify readiness, forwards, routes, TLS, and dashboard boundaries
   before changing DNS.
5. Roll back by stopping the MicroVM and restoring the previous process and
   configuration. Osmium does not delete external files, ACME state, or provider
   resources.

## Checks

```sh
nix build .#checks.x86_64-linux.traefik --print-build-logs
nix build .#checks.x86_64-linux.traefik-drift-reverse-configuration --print-build-logs
nix build .#checks.x86_64-linux.traefik-live-capture-reverse-configuration --print-build-logs
```

The ordinary check boots Traefik, verifies readiness and routing, checks the
dashboard loopback boundary, and verifies persistent state after restart and
reboot. Reverse-configuration checks are review-only: provider-generated
objects, generated certificates, missing source files, and unavailable secret
references are recorded as explicit blockers rather than claimed to be fully
replayable.
