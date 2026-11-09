{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.osmium.traefik;
  entrypoints = lib.attrValues cfg.entrypoints;
  dashboardRouterName = "osmium-traefik-dashboard";
  dashboardEnabled = cfg.dashboard.enable;
  generatedStaticConfig = lib.recursiveUpdate
    (lib.optionalAttrs cfg.readiness.enable {
      entryPoints.${cfg.readiness.entrypoint}.address = "127.0.0.1:${toString cfg.readiness.port}";
      ping.entryPoint = cfg.readiness.entrypoint;
    })
    (lib.optionalAttrs dashboardEnabled {
      api.dashboard = true;
      entryPoints.${cfg.dashboard.entrypoint}.address =
        if cfg.dashboard.exposure == "entrypoint"
        then ":${toString cfg.dashboard.port}"
        else "127.0.0.1:${toString cfg.dashboard.port}";
    });
  generatedDynamicConfig = lib.optionalAttrs dashboardEnabled {
    http.routers.${dashboardRouterName} = {
      rule = "PathPrefix(`/dashboard`) || PathPrefix(`/api`)";
      service = "api@internal";
      entryPoints = [ cfg.dashboard.entrypoint ];
    } // lib.optionalAttrs (cfg.dashboard.middleware != null) {
      middlewares = [ cfg.dashboard.middleware ];
      };
    };
  declaredEntryPointDefaults = {
    entryPoints = lib.mapAttrs
      (name: entrypoint: {
        address = ":${toString entrypoint.guestPort}${lib.optionalString (entrypoint.protocol == "udp") "/udp"}";
      })
      (lib.filterAttrs (name: _: !(lib.hasAttrByPath [ "entryPoints" name "address" ] cfg.staticConfigOptions)) cfg.entrypoints);
  };
  effectiveStaticConfig = lib.recursiveUpdate
    (lib.recursiveUpdate declaredEntryPointDefaults cfg.staticConfigOptions)
    generatedStaticConfig;
  effectiveDynamicConfig = lib.recursiveUpdate cfg.dynamicConfigOptions generatedDynamicConfig;
  observeTool = pkgs.writeShellScriptBin "osmium-traefik-observe" ''
    exec ${pkgs.python3}/bin/python ${../../tools/traefik_observe.py} "$@"
  '';
in
{
  options.services.osmium.traefik = {
    enable = lib.mkEnableOption "the Osmium Traefik service";

    package = lib.mkPackageOption pkgs "traefik" { };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/traefik";
      description = "Persistent Traefik state directory.";
    };

    staticConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Runtime/static Traefik configuration file.";
    };

    staticConfigOptions = lib.mkOption {
      type = options.services.traefik.staticConfigOptions.type;
      default = { };
      description = "Static Traefik configuration passed to the upstream module.";
    };

    dynamicConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Runtime/dynamic Traefik configuration file.";
    };

    dynamicConfigOptions = lib.mkOption {
      type = options.services.traefik.dynamicConfigOptions.type;
      default = { };
      description = "Dynamic Traefik configuration passed to the upstream module.";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Runtime environment files consumed by Traefik.";
    };

    entrypoints = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          guestPort = lib.mkOption { type = lib.types.port; description = "Guest port for the Traefik entrypoint."; };
          hostPort = lib.mkOption { type = lib.types.nullOr lib.types.port; default = null; description = "Optional MicroVM host-forwarded port."; };
          protocol = lib.mkOption { type = lib.types.enum [ "tcp" "udp" ]; default = "tcp"; description = "Forwarding protocol."; };
        };
      }));
      default = { };
      description = "Explicit guest entrypoints and optional host forwards.";
    };

    readiness = {
      enable = lib.mkEnableOption "the local Traefik readiness endpoint" // { default = true; };
      entrypoint = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "osmium-readiness"; description = "Loopback readiness entrypoint name."; };
      port = lib.mkOption { type = lib.types.port; default = 8080; description = "Loopback readiness port."; };
    };

    dashboard = {
      enable = lib.mkEnableOption "the Traefik dashboard/API";
      exposure = lib.mkOption { type = lib.types.enum [ "loopback" "entrypoint" ]; default = "loopback"; description = "Dashboard exposure boundary."; };
      entrypoint = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9._-]+"; default = "osmium-dashboard"; description = "Dashboard entrypoint name."; };
      port = lib.mkOption { type = lib.types.port; default = 8081; description = "Loopback dashboard port."; };
      hostPort = lib.mkOption { type = lib.types.nullOr lib.types.port; default = null; description = "Optional host-forwarded dashboard port."; };
      middleware = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Traefik middleware required for entrypoint dashboard exposure."; };
    };
  };

  config = lib.mkIf cfg.enable ({
    assertions = [
      { assertion = lib.hasPrefix "/var/lib/" (toString cfg.dataDir); message = "services.osmium.traefik.dataDir must be below /var/lib."; }
      { assertion = cfg.staticConfigFile == null || !cfg.readiness.enable; message = "Traefik readiness generation requires staticConfigFile = null."; }
      { assertion = cfg.dynamicConfigFile == null || !dashboardEnabled; message = "Traefik dashboard generation requires dynamicConfigFile = null."; }
      { assertion = lib.all (path: !lib.hasPrefix "/nix/store/" (toString path)) cfg.environmentFiles; message = "Traefik environmentFiles must reference runtime paths outside the Nix store."; }
      { assertion = cfg.dashboard.exposure != "entrypoint" || cfg.dashboard.middleware != null; message = "Traefik dashboard entrypoint exposure requires a middleware."; }
      { assertion = !dashboardEnabled || lib.attrByPath [ "http" "routers" dashboardRouterName ] null cfg.dynamicConfigOptions == null; message = "Traefik dashboard router name is reserved."; }
      { assertion = lib.length (map (entrypoint: entrypoint.guestPort) entrypoints) == lib.length (lib.unique (map (entrypoint: entrypoint.guestPort) entrypoints)); message = "Traefik guest entrypoint ports must be unique."; }
      { assertion = lib.length (lib.filter (hostPort: hostPort != null) (map (entrypoint: entrypoint.hostPort) entrypoints)) == lib.length (lib.unique (lib.filter (hostPort: hostPort != null) (map (entrypoint: entrypoint.hostPort) entrypoints))); message = "Traefik host-forwarded ports must be unique."; }
      { assertion = cfg.dashboard.hostPort == null || cfg.dashboard.exposure == "entrypoint"; message = "Traefik dashboard hostPort requires entrypoint exposure."; }
      { assertion = cfg.dashboard.hostPort == null || !(lib.elem cfg.dashboard.hostPort (map (entrypoint: entrypoint.hostPort) entrypoints)); message = "Traefik dashboard hostPort collides with an entrypoint host port."; }
    ];

    services.traefik = {
      enable = true;
      package = cfg.package;
      dataDir = cfg.dataDir;
      group = "traefik";
      staticConfigFile = cfg.staticConfigFile;
      staticConfigOptions = effectiveStaticConfig;
      dynamicConfigFile = cfg.dynamicConfigFile;
      dynamicConfigOptions = effectiveDynamicConfig;
      environmentFiles = cfg.environmentFiles;
    };

    environment.systemPackages = [ observeTool ];

    systemd.services.traefik.serviceConfig = {
      RestartSec = "2s";
      TimeoutStopSec = "30s";
    };

    environment.persistence."/persistent".directories = [
      { directory = cfg.dataDir; user = "traefik"; group = "traefik"; mode = "0700"; }
    ];
  } // lib.optionalAttrs (options ? microvm) {
    microvm.forwardPorts = lib.concatLists [
      (lib.map (entrypoint: {
        from = "host";
        proto = entrypoint.protocol;
        host.port = entrypoint.hostPort;
        guest.port = entrypoint.guestPort;
      }) (lib.filter (entrypoint: entrypoint.hostPort != null) entrypoints))
      (lib.optional (cfg.dashboard.exposure == "entrypoint" && cfg.dashboard.hostPort != null) {
        from = "host";
        proto = "tcp";
        host.port = cfg.dashboard.hostPort;
        guest.port = cfg.dashboard.port;
      })
    ];
    networking.firewall.allowedTCPPorts =
      (lib.map (entrypoint: entrypoint.guestPort) (lib.filter (entrypoint: entrypoint.protocol == "tcp") entrypoints))
      ++ lib.optional (cfg.dashboard.exposure == "entrypoint") cfg.dashboard.port;
    networking.firewall.allowedUDPPorts = lib.map (entrypoint: entrypoint.guestPort) (lib.filter (entrypoint: entrypoint.protocol == "udp") entrypoints);
  });
}
